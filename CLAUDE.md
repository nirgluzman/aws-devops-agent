# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS DevOps Agent demonstration: serverless message API (API Gateway → Lambda → S3) with deliberate fault injection to showcase autonomous root-cause analysis via X-Ray traces, CloudWatch logs, and GitHub integration.

**Region**: `us-east-1` (required for DevOps Agent preview).

**GitHub Repository**: https://github.com/nirgluzman/aws-devops-agent.git

**IMPORTANT**: Do NOT auto-commit or push to this repo without explicit permission. Keep the commit history concise and clean.

**Documentation**: See `docs/` for detailed guides:
- `architecture.md` — Technical deep-dive with ASCII diagrams
- `demo-guide.md` — Step-by-step deployment and testing runbook
- `aws-devops-agent-overview.md` — DevOps Agent capabilities and security model
- `github-actions-setup.md` — CI/CD workflow configuration

## Prerequisites & Setup

### AWS DevOps Agent (Agent Space) Setup

1. **Create Agent Space** (https://console.aws.amazon.com/devops-agent/home?region=us-east-1)
   - Agent Spaces are logical security boundaries with isolated configurations
   - Each space operates independently with its own AWS account connections

2. **Connect AWS Account**
   - Auto-discovers all AWS resources (Lambda, CloudWatch, X-Ray, S3, API Gateway, SNS)
   - No per-service configuration needed
   - Uses IAM role for read-only access

3. **(Recommended) Connect Slack or ServiceNow**
   - Without integration: Must manually check Agent Space UI for RCA findings
   - With integration: Automated notifications of investigation results
   - Email/SNS do NOT support RCA notifications (only alarm status)

4. **(Optional) Connect GitHub Repository**
   - Enables code change correlation during investigations
   - Tracks deployments via GitHub Actions artifacts
   - Helps identify if recent commits caused incidents

### GitHub Actions Configuration

Configure under *Settings → Secrets and variables → Actions*:

| Name | Type | Example | Purpose |
|------|------|---------|---------|
| `AWS_ROLE_ARN` | Secret | `arn:aws:iam::123456789012:role/github-actions-terraform` | OIDC role assumption |
| `AWS_REGION` | Variable | `us-east-1` | Target region |
| `ALERT_EMAIL` | Variable | `ops-team@example.com` | SNS email subscription |
| `TF_STATE_BUCKET` | Variable | `terraform-backend-demo-ue1` | S3 backend bucket |

See `docs/github-actions-setup.md` for complete OIDC setup guide.

## Common Commands

### Lambda Development

```bash
# Build Lambda function (TypeScript → JavaScript via esbuild)
cd backend/functions/handle_messages
npm ci
npm run build

# Package for deployment
zip -r ../../../terraform/lambda.zip dist/index.js package.json
```

### Terraform Operations

```bash
cd terraform

# Initialize with remote state
terraform init -backend-config="bucket=YOUR_STATE_BUCKET"

# Plan changes
terraform plan -var="alert_email=YOUR_EMAIL"

# Deploy all modules
terraform apply -auto-approve -var="alert_email=YOUR_EMAIL"

# Destroy all infrastructure
terraform destroy -auto-approve
```

### Fault Injection

```bash
# Inject S3 bucket policy fault (deny Lambda access)
python scripts/break_s3_policy.py \
  --bucket-name BUCKET_NAME \
  --lambda-role-arn LAMBDA_ROLE_ARN

# Restore S3 bucket policy
python scripts/restore_s3_policy.py --bucket-name BUCKET_NAME

# Smoke test API
bash scripts/smoke-test.sh https://API_URL/dev
```

### Terraform Outputs (Save After Deploy)

After deploying via GitHub Actions, save these outputs from workflow logs:
- `api_url` — API Gateway endpoint for testing
- `lambda_function_name` — Lambda function name for CloudWatch logs
- `lambda_role_arn` — IAM role ARN (needed for fault injection)
- `s3_bucket_id` — S3 bucket name (needed for fault injection)
- `sns_topic_arn` — SNS topic ARN for alarm notifications
- `error_alarm_arn` — CloudWatch error alarm ARN
- `duration_alarm_arn` — CloudWatch duration alarm ARN

## Architecture Overview

### Three-Module Terraform Structure

1. **app_stack** (`terraform/modules/app_stack/`)
   - API Gateway (HTTP v2, `GET/POST /messages`)
   - Lambda function (Node.js 24.x, TypeScript, esbuild)
   - S3 bucket (message storage)
   - Dependencies: None (deployed first)

2. **notification** (`terraform/modules/notification/`)
   - SNS topic + email subscription
   - Dependencies: None (deployed first)

3. **observability** (`terraform/modules/observability/`)
   - CloudWatch alarms (Errors, Duration)
   - Log metric filters
   - Dependencies: `app_stack.lambda_function_name`, `notification.sns_topic_arn`

**Module Wiring:** `terraform/main.tf` orchestrates all three modules in a single state file.

### Lambda Function Flow

```
API Gateway → Lambda (handle_messages) → S3 bucket
                 ├── X-Ray: Powertools Tracer + Middy middleware
                 ├── Custom subsegments: S3-ListObjects, S3-PutObject
                 └── CloudWatch Logs (3-day retention)
```

**Handler:** `backend/functions/handle_messages/src/index.ts`
- `GET /messages`: Lists S3 objects via `ListObjectsV2Command`
- `POST /messages`: Stores message via `PutObjectCommand` with UUID + timestamp

**Key Instrumentation:**
- X-Ray tracing via `@aws-lambda-powertools/tracer` (captures cold starts, S3 calls, errors)
- Middy middleware pattern: `middy(lambdaHandler).use(captureLambdaHandler(tracer))`
- Custom subsegments for granular S3 operation visibility

### Build System

**esbuild Configuration** (`backend/functions/handle_messages/build.js`):
- Bundles **everything** including AWS SDK v3 (`external: []`)
- Why: ~1.7x faster cold starts, pinned SDK version, tree-shaken bundle
- Target: Node.js 24.x
- Output: Single minified `dist/index.js` (~725 KB)

## Critical Design Decisions

### AWS SDK Bundling

**Always bundle AWS SDK v3** (`external: []` in esbuild). Lambda runtime SDK is often outdated and missing security patches. Bundling provides faster cold starts and version control.

### Terraform Backend

Uses S3-native locking (Terraform 1.10+, `use_lockfile = true`) — no DynamoDB table needed. Backend bucket is overridden in CI/CD via `-backend-config="bucket=${{ vars.TF_STATE_BUCKET }}"`.

### Fault Injection Strategy

**S3 Bucket Policy** (not IAM role modification):
- Injects explicit `Deny` statement on `s3:GetObject/PutObject/ListBucket` for Lambda role
- Explicit Deny overrides IAM Allow → `AccessDenied` errors
- Reversible without redeployment
- Demonstrates infrastructure misconfiguration (not code bug)

Scripts:
- `break_s3_policy.py`: Saves original policy, injects Deny statement
- `restore_s3_policy.py`: Restores original policy or removes Deny by Sid

### X-Ray Instrumentation Best Practices

1. **Use Powertools Tracer** (not raw X-Ray SDK) — AWS-recommended, auto-captures cold starts
2. **Wrap S3 client**: `tracer.captureAWSv3Client(new S3Client({}))`
3. **Custom subsegments** for granular operation visibility:
   ```typescript
   const subsegment = tracer.provider.getSegment()!.addNewSubsegment('S3-PutObject');
   try {
     await client.send(command);
     subsegment.close();
   } catch (error) {
     subsegment.addError(error as Error);
     subsegment.close();
     throw error;
   }
   ```

### HTTP API (not REST API)

Chose HTTP API v2 for:
- 71% cheaper ($1/million vs $3.50/million)
- Lower latency (native `AWS_PROXY` support)
- Sufficient for simple proxy use cases

## CI/CD Workflows

### GitHub Actions Authentication

**OIDC-based** (no long-lived credentials):
- Workflow requires `id-token: write` permission
- Uses `aws-actions/configure-aws-credentials@v5` with `role-to-assume`
- Trust policy restricts to specific repo + branch

### Workflows

1. **deploy-app.yml** (unified deploy)
   - Trigger: Push to `main` (paths: `backend/**`, `terraform/modules/**`, `terraform/main.tf`) or manual
   - Steps: Build Lambda → Terraform apply (all modules)
   - **Critical:** Pre-builds Lambda zip to avoid Terraform hash drift

2. **inject-fault.yml** (manual)
   - Inputs: `bucket_name`, `lambda_role_arn`
   - Runs: `break_s3_policy.py`

3. **smoke-test.yml** (manual)
   - Input: `api_url`
   - Tests GET/POST endpoints

4. **destroy-all.yml** (manual)
   - Runs: `terraform destroy -auto-approve`
   - S3 buckets auto-empty (`force_destroy = true`)

## DevOps Agent Integration

### Resource Discovery

**AWS Services (Automatic):** All AWS resources are auto-discovered via the connected AWS account's IAM role:
- CloudWatch (alarms, logs, metrics)
- X-Ray (traces, service maps)
- Lambda (functions, invocations)
- S3 (buckets, operations)
- API Gateway (endpoints, requests)
- SNS (topics, subscriptions)

**No additional per-service configuration needed** — Agent Space discovers AWS resources automatically once the AWS account is connected.

**3rd Party Integrations (Requires Configuration):**
- GitHub, GitLab (code change correlation)
- Slack (RCA notifications)
- ServiceNow (bidirectional ticket updates)
- PagerDuty, Jira (incident tracking)

### Investigation Flow

**Trigger:** CloudWatch alarm fires → Agent Space automatically initiates investigation

**Analysis Process:**
1. Agent queries X-Ray traces → identifies `AccessDenied` errors on S3 operations
2. Agent queries CloudWatch Logs → retrieves detailed stack traces and error messages
3. Agent queries GitHub (if connected) → correlates recent S3-related commits
4. Agent produces Root Cause Analysis (RCA): "S3 bucket policy denies Lambda role access"
5. Agent generates mitigation plan with Prepare/Pre-Validate/Apply/Post-Validate steps

### Notification Architecture

**IMPORTANT:** DevOps Agent does **NOT** send RCA findings via SNS or email.

**How This Demo Works:**
```
CloudWatch Alarm → SNS Topic → Email (alarm status only)
       ↓
  Agent Space receives trigger
       ↓
  Agent performs RCA
       ↓
Agent Space UI + Slack/ServiceNow (detailed findings)
```

**Notification Channels:**

| Channel | Investigation Results | Setup Required |
|---------|----------------------|----------------|
| **Agent Space Web UI** | ✅ Always available | None (default) |
| **Slack** | ✅ Automated RCA posts | Agent Space → Integrations → Slack |
| **ServiceNow** | ✅ Bidirectional ticket updates | Agent Space → Integrations → ServiceNow |
| **Email/SNS** | ❌ Alarm status only (not RCA) | N/A — use Slack/ServiceNow instead |

**Recommendation:** Configure Slack or ServiceNow integration to receive automated RCA notifications. Without these integrations, teams must manually check Agent Space UI for investigation results.

### Security Model

**Primary Region:** All processing occurs in `us-east-1` (preview requirement)

**IAM Permissions:** Agent uses read-only IAM roles with least-privilege access:
- Primary account role: Discovers AWS resources (CloudWatch, X-Ray, Lambda, etc.)
- Secondary account roles: Multi-account support (if needed)
- Web app role: User authentication via IAM Identity Center or IAM auth link

**Prompt Injection Protection:**
- Limited write capabilities (cannot modify/delete infrastructure)
- Immutable audit trail (Agent Journal logs every action)
- AI Safety Level 3 (ASL-3) protections via Claude Sonnet 4.5

**Data Security:**
- Encrypted at rest (AWS-managed keys)
- Encrypted in transit across private network
- Customer responsible for PII redaction in logs before ingestion

## Observability Strategy

### CloudWatch Alarms

**Error Alarm:**
- Metric: `AWS/Lambda` → `Errors`
- Threshold: `Sum >= 1` in 60s (zero-tolerance for demo)

**Duration Alarm:**
- Metric: `AWS/Lambda` → `Duration`
- Threshold: `p99 > 5000ms` in 60s

Both send to SNS on `alarm_actions` + `ok_actions`.

### Log Metric Filter

Pattern: `"ERROR"` (case-sensitive), creates custom metric from log entries.

## File Structure

```
aws-devops-agents/
├── backend/functions/handle_messages/
│   ├── src/index.ts              # Lambda handler (TypeScript)
│   ├── build.js                  # esbuild config (bundles AWS SDK)
│   ├── package.json
│   └── tsconfig.json
├── terraform/
│   ├── main.tf                   # Root module (orchestrates 3 modules)
│   ├── backend.tf                # S3 remote state (native locking)
│   ├── providers.tf              # AWS provider (default_tags)
│   ├── global_tags.tf            # Default tags for all resources
│   ├── variables.tf / outputs.tf # Root inputs/outputs
│   └── modules/
│       ├── app_stack/            # API GW + Lambda + S3
│       │   ├── apigw.tf          # API Gateway HTTP v2
│       │   ├── lambda.tf         # Lambda function
│       │   ├── s3.tf             # S3 message bucket
│       │   ├── variables.tf      # Module inputs
│       │   └── outputs.tf        # Module outputs
│       ├── notification/         # SNS topic + email subscription
│       │   ├── main.tf           # SNS resources
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── observability/        # CloudWatch alarms + log filters
│           ├── main.tf           # CloudWatch resources
│           ├── variables.tf
│           └── outputs.tf
├── scripts/
│   ├── break_s3_policy.py        # Fault injection
│   ├── restore_s3_policy.py      # Fault remediation
│   └── smoke-test.sh             # API smoke test
├── .github/workflows/
│   ├── deploy-app.yml            # Unified build + deploy
│   ├── inject-fault.yml          # Fault injection workflow
│   ├── smoke-test.yml            # Smoke test workflow
│   └── destroy-all.yml           # Teardown workflow
└── docs/
    ├── architecture.md           # Technical deep-dive (ASCII diagrams)
    ├── demo-guide.md             # Step-by-step deployment runbook
    ├── aws-devops-agent-overview.md  # Agent capabilities & security
    ├── github-actions-setup.md   # CI/CD configuration guide
    ├── assets/                   # Exported diagram images (JPG)
    │   ├── 01-demo-overview.jpg
    │   ├── 02-system-architecture.jpg
    │   └── 03-fault-injection-flow.jpg
    └── diagrams/                 # Editable draw.io source files
        ├── 01-demo-overview.drawio
        ├── 02-system-architecture.drawio
        ├── 03-fault-injection-flow.drawio
        └── README.md
```

## Required GitHub Actions Secrets/Variables

**Secrets:**
- `AWS_ROLE_ARN`: IAM role ARN for OIDC authentication

**Variables:**
- `AWS_REGION`: Target region (typically `us-east-1`)
- `ALERT_EMAIL`: SNS email subscription endpoint
- `TF_STATE_BUCKET`: S3 bucket for Terraform remote state

## Tags

All resources tagged via `provider.default_tags`:
- `Project = DevOpsAgentDemo` (cost tracking)
- `Terraform = true` (IaC identification)
- `Environment = dev` (environment label)

## Important Notes

1. **Never use `force_destroy = true` in production** — demo convenience only (allows Terraform destroy without manual S3 emptying)

2. **SNS email subscription requires manual confirmation** — check inbox after first `terraform apply`

3. **Lambda zip must be pre-built in CI/CD** — prevents `source_code_hash` drift during apply

4. **All modules share one Terraform state** — unified deploy workflow prevents state conflicts

5. **S3-native locking requires Terraform 1.10+** — no DynamoDB table needed

6. **Bundle AWS SDK v3 in Lambda** — faster cold starts, version control, security patches

7. **DevOps Agent RCA not sent via email** — Must configure Slack/ServiceNow or check Agent Space UI manually

## Success Criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| 1 | API returns `200` on GET/POST | `bash scripts/smoke-test.sh <api_url>` |
| 2 | X-Ray traces show custom subsegments | X-Ray console → Service map → Lambda → Subsegments |
| 3 | CloudWatch alarm fires on fault | CloudWatch console → Alarms → Status: ALARM |
| 4 | Email notification received | Check inbox for SNS alarm notification |
| 5 | Agent produces RCA | Agent Space UI → Investigations → View RCA |
| 6 | Agent identifies bucket policy as root cause | RCA content mentions S3 bucket policy denial |

## Verification Steps

### Smoke Test (Healthy State)
```bash
# Run automated smoke test
bash scripts/smoke-test.sh https://YOUR_API_URL/dev

# Or manual cURL tests
curl -X GET "https://YOUR_API_URL/dev/messages"  # Expect: 200, []
curl -X POST "https://YOUR_API_URL/dev/messages" -d '{"message":"test"}'  # Expect: 200
```

### X-Ray Verification
1. [X-Ray Console](https://console.aws.amazon.com/xray/home?region=us-east-1#/service-map)
2. Verify service map: API Gateway → Lambda → S3
3. Click Lambda segment → Subsegments → Confirm `S3-ListObjects`, `S3-PutObject`

### Agent Space Verification
1. [Agent Space Console](https://console.aws.amazon.com/devops-agent/home?region=us-east-1)
2. After fault injection: Wait ~2 minutes for investigation
3. Check Investigations tab → View RCA findings
4. Verify root cause: "S3 bucket policy denies Lambda role access"
