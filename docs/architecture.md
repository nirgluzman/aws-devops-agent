# AWS DevOps Agent Demo - Technical Architecture

This document describes the technical architecture, component interactions, and design decisions for the AWS DevOps Agent demonstration.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture Diagrams](#architecture-diagrams)
3. [Component Details](#component-details)
4. [Terraform Module Architecture](#terraform-module-architecture)
5. [X-Ray Instrumentation](#x-ray-instrumentation)
6. [Observability Strategy](#observability-strategy)
7. [Fault Injection Mechanism](#fault-injection-mechanism)
8. [Tagging Strategy](#tagging-strategy)
9. [CI/CD Pipeline](#cicd-pipeline)
10. [Technical Decisions](#technical-decisions)

---

## System Overview

The demo deploys a serverless message API that deliberately fails via S3 bucket policy injection, allowing AWS DevOps Agent to demonstrate autonomous root-cause analysis using X-Ray traces, CloudWatch logs, and GitHub integration.

**Region:** All infrastructure deploys to `us-east-1`. While DevOps Agent can monitor resources in any region, we use a single region to keep the demo simple.

**Core Flow:**
1. Healthy API (API Gateway → Lambda → S3) serves GET/POST requests
2. Fault injection denies S3 access via bucket policy
3. Lambda throws `AccessDenied` errors → CloudWatch alarm fires
4. SNS sends email notification
5. DevOps Agent correlates X-Ray traces + CloudWatch logs + GitHub commits
6. Agent produces root-cause analysis with actionable remediation

---

## Architecture Diagrams

### High-Level System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          CLIENT                                  │
└────────────┬─────────────────────────────────────────────────────┘
             │ HTTP (GET/POST /messages)
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     API Gateway (HTTP v2)                       │
│                          /dev stage                             │
│  Routes: GET /messages, POST /messages                          │
└────────────┬────────────────────────────────────────────────────┘
             │ AWS_PROXY integration
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                Lambda Function (handle_messages)                │
│                     Node.js 24.x, TypeScript                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Business Logic:                                           │  │
│  │  - GET: List messages from S3                             │  │
│  │  - POST: Store message to S3 as JSON                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Instrumentation:                                          │  │
│  │  - X-Ray tracing (Powertools Tracer + Middy)              │  │
│  │  - Custom subsegments (S3-ListObjects, S3-PutObject)      │  │
│  │  - CloudWatch Logs (3-day retention)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────┬────────────────────────────────────────────────────┘
             │ S3 API calls
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    S3 Bucket (messages-*)                       │
│  - Stores messages as JSON objects                              │
│  - Bucket policy: Allow Lambda role (normal state)              │
│  - Bucket policy: DENY Lambda role (fault injected)             │
└─────────────────────────────────────────────────────────────────┘
```

### Observability & Incident Response Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Lambda Execution                             │
│  (S3 AccessDenied error thrown when fault is active)            │
└──────┬──────────────────────────┬───────────────────────────────┘
       │                          │
       │ Metrics                  │ Traces
       ▼                          ▼
┌──────────────────┐      ┌──────────────────────────────────────┐
│  CloudWatch      │      │          X-Ray Service               │
│  Metrics         │      │  - Trace segments (API GW → Lambda)  │
│                  │      │  - Custom subsegments (S3 ops)       │
│  AWS/Lambda:     │      │  - Error capture (AccessDenied)      │
│   - Errors       │      │  - Service map visualization         │
│   - Duration     │      └──────────────────────────────────────┘
└──────┬───────────┘
       │
       │ Alarm evaluation (60s period)
       ▼
┌──────────────────────────────────────────────────────────────────┐
│              CloudWatch Alarms                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Error Alarm: Errors (Sum) >= 1                             │  │
│  │ Duration Alarm: Duration (p99) > 5000ms                    │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────┬───────────────────────────────────────────────────────────┘
       │ alarm_actions / ok_actions
       ▼
┌──────────────────────────────────────────────────────────────────┐
│              SNS Topic (devops-agent-alerts)                     │
│  - Protocol: email                                               │
│  - Subscription: ops team email (requires confirmation)          │
└──────┬───────────────────────────────────────────────────────────┘
       │
       ├─────────────────┐
       │                 │
       ▼                 ▼
┌──────────────┐   ┌─────────────────────────────────────────────┐
│    Email     │   │    AWS DevOps Agent (Agent Space)           │
│ Notification │   │                                             │
└──────────────┘   │  Data Sources:                              │
                   │   - X-Ray traces (error correlation)        │
                   │   - CloudWatch Logs (error details)         │
                   │   - GitHub (change correlation)             │
                   │                                             │
                   │  Autonomous Investigation:                  │
                   │   1. Detects incident from alarm            │
                   │   2. Correlates traces + logs + commits     │
                   │   3. Identifies S3 policy as root cause     │
                   │   4. Produces RCA with remediation steps    │
                   └─────────────────────────────────────────────┘
```

### Terraform Module Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                    terraform/main.tf (root)                     │
│                                                                 │
│  Orchestrates 3 modules:                                        │
│   - app_stack                                                   │
│   - notification                                                │
│   - observability                                               │
└──────────┬──────────────────┬────────────────────┬──────────────┘
           │                  │                    │
           ▼                  ▼                    ▼
    ┌─────────────┐   ┌──────────────┐   ┌──────────────────────┐
    │  app_stack  │   │ notification │   │   observability      │
    │             │   │              │   │                      │
    │ Outputs:    │   │ Outputs:     │   │ Inputs:              │
    │ - lambda_   │   │ - sns_topic_ │   │ - lambda_function_   │
    │   function_ │   │   arn        │   │   name (from app_    │
    │   name      │   │              │   │   stack)             │
    │ - lambda_   │   │              │   │ - sns_topic_arn      │
    │   role_arn  │   │              │   │   (from notification)│
    │ - api_url   │   │              │   │                      │
    │ - s3_bucket_│   │              │   │ Outputs:             │
    │   id/arn    │   │              │   │ - error_alarm_arn    │
    │             │   │              │   │ - duration_alarm_arn │
    └─────────────┘   └──────────────┘   └──────────────────────┘
         │                   │                      │
         │                   └──────────┬───────────┘
         │                              │
         └──────────────────────────────┘
                        │
                        ▼
              Inter-module wiring in
              terraform/main.tf
```

### CI/CD Workflow Paths

```
GitHub Repository (main branch)
    │
    ├─── Push to backend/**, terraform/modules/**, or terraform/main.tf
    │    │
    │    ▼
    │    ┌──────────────────────────────────────────────────────┐
    │    │  Workflow: deploy-app.yml (unified)                  │
    │    │  1. Build Lambda (npm ci + npm run build)            │
    │    │  2. Terraform init (with backend-config)             │
    │    │  3. Terraform apply -auto-approve                    │
    │    │  → Deploys: API GW + Lambda + S3 + CloudWatch + SNS  │
    │    └──────────────────────────────────────────────────────┘
    │
    ├─── Manual trigger: workflow_dispatch
    │    │
    │    ▼
    │    ┌──────────────────────────────────────────────────────┐
    │    │  Workflow: inject-fault.yml                          │
    │    │  Inputs: bucket_name, lambda_role_arn                │
    │    │  → Runs: break_s3_policy.py                          │
    │    │  → Result: S3 policy DENIES Lambda access            │
    │    └──────────────────────────────────────────────────────┘
    │
    └─── Manual trigger: workflow_dispatch
         │
         ▼
         ┌──────────────────────────────────────────────────────┐
         │  Workflow: destroy-all.yml                           │
         │  → Runs: terraform destroy -auto-approve             │
         │  → Removes all infrastructure                        │
         └──────────────────────────────────────────────────────┘
```

---

## Component Details

### API Gateway (HTTP API v2)

**Type:** HTTP API (not REST API) — simpler, lower-cost, better performance for proxy integrations

**Configuration:**
- Stage: `dev`
- Routes:
  - `GET /messages` → Lambda integration
  - `POST /messages` → Lambda integration
- Integration type: `AWS_PROXY` (passes full request to Lambda)
- CORS: Disabled (demo only, no browser client)

**Why HTTP API?**
- Cheaper than REST API ($1/million vs $3.50/million)
- Native AWS_PROXY support with minimal config
- Sufficient for simple proxy use cases

### Lambda Function (handle_messages)

**Runtime:** Node.js 24.x (latest LTS)

**Handler:** `index.handler`

**Memory:** 128 MB (default, sufficient for S3 operations)

**Timeout:** 6 seconds

**Environment Variables:** `MESSAGES_BUCKET` (S3 bucket name, set by Terraform)

**IAM Permissions:**
- `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on messages bucket
- `xray:PutTraceSegments`, `xray:PutTelemetryRecords` (tracing)
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` (logging)

**Build Process:**
- TypeScript → JavaScript via esbuild
- **Bundles everything** including AWS SDK v3 (see Technical Decisions)
- Minified output: ~725 KB
- External dependencies: None (all bundled)

**Business Logic:**
- `GET /messages`: Lists all objects in S3 bucket, returns JSON array
- `POST /messages`: Accepts JSON body, stores as S3 object with timestamp

### S3 Bucket (messages-*)

**Naming:** `random_pet` suffix for uniqueness (e.g., `messages-bucket-happy-noble-otter`)

**Configuration:**
- Versioning: Disabled (demo, not production)
- Encryption: Default (SSE-S3)
- Public access: Blocked (all 4 settings)
- `force_destroy = true` (allows Terraform destroy without manual emptying)

**Bucket Policy (normal state):** None or permissive for Lambda role

**Bucket Policy (fault state):** Explicit Deny for Lambda role on `s3:GetObject`, `s3:PutObject`, `s3:ListBucket`

### CloudWatch Components

**Log Group:**
- Name: `/aws/lambda/handle_messages_*`
- Retention: 3 days (demo only)
- Used by: DevOps Agent for error log correlation

**Metric Alarms:**

1. **Error Alarm**
   - Metric: `AWS/Lambda` → `Errors`
   - Statistic: `Sum`
   - Period: 60 seconds
   - Threshold: `>= 1` error
   - Actions: `alarm_actions` + `ok_actions` → SNS topic

2. **Duration Alarm**
   - Metric: `AWS/Lambda` → `Duration`
   - Statistic: `p99` (99th percentile)
   - Period: 60 seconds
   - Threshold: `> 5000` milliseconds
   - Actions: `alarm_actions` + `ok_actions` → SNS topic

**Log Metric Filter:**
- Pattern: `"ERROR"` (matches log entries containing "ERROR")
- Metric namespace: Custom
- Used for: Additional error detection beyond Lambda metrics

### SNS Topic (devops-agent-alerts)

**Configuration:**
- Name: `devops-agent-alerts`
- Protocol: `email`
- Endpoint: From `var.alert_email` (GitHub Actions variable)

**Subscription Confirmation:**
- AWS sends confirmation email on first `terraform apply`
- Status: `PendingConfirmation` until user clicks link
- **Critical:** Notifications will NOT be delivered until confirmed

**Notification Content:**
- Alarm state changes (OK → ALARM, ALARM → OK)
- **Does NOT include DevOps Agent RCA findings** (those appear only in Agent Space UI)

**Investigation Result Notifications:**

DevOps Agent investigation findings are **NOT sent via SNS/email**. Supported notification channels:

| Channel | Investigation Results | Setup |
|---------|----------------------|-------|
| **Slack** | ✅ Automated posts to channel | Agent Space → Integrations → Slack |
| **ServiceNow** | ✅ Added to incident tickets | Agent Space → Integrations → ServiceNow |
| **Email/SNS** | ❌ Not supported | Use Slack/ServiceNow instead |
| **Agent Space UI** | ✅ Always available | Manual check required |

**Recommendation for production:** Configure Slack or ServiceNow integration to receive automated RCA notifications. Without these integrations, teams must manually check Agent Space UI for investigation results.

### X-Ray Service

**Tracing Mode:** Active (set via `tracing_mode = "Active"` in Lambda config)

**Integration:** AWS Lambda Powertools Tracer (TypeScript)

**Captured Data:**
- Lambda cold starts (automatic via Powertools)
- API Gateway → Lambda calls (automatic)
- Lambda → S3 API calls (automatic via `tracer.captureAWSv3Client()`)
- Custom subsegments: `S3-ListObjects`, `S3-PutObject` (manual instrumentation)
- Error capture: `AccessDenied` exceptions with stack traces

**Why Custom Subsegments?**
- Provides granular visibility into individual S3 operations
- Makes it easier for DevOps Agent to pinpoint which S3 call failed
- Demonstrates Powertools best practices

---

## Terraform Module Architecture

### Module: `app_stack`

**Purpose:** Deploys the core application infrastructure (API Gateway, Lambda, S3)

**Resources:**
- `module.lambda` (terraform-aws-modules/lambda/aws ~8.0)
- `module.api_gateway` (terraform-aws-modules/apigateway-v2/aws ~6.0)
- `module.s3_bucket` (terraform-aws-modules/s3-bucket/aws ~5.0)
- IAM roles and policies for Lambda execution

**Key Configuration:**
```hcl
# Lambda
create_package         = false
local_existing_package = "${path.root}/lambda.zip"  # Pre-built in CI
runtime     = "nodejs24.x"
handler     = "dist/index.handler"
tracing_mode = "Active"

# API Gateway
protocol_type = "HTTP"
routes = {
  "GET /messages"  = { integration = { uri = lambda_arn } }
  "POST /messages" = { integration = { uri = lambda_arn } }
}

# S3
force_destroy = true  # Demo convenience
```

**Inputs:**
- `aws_region` (string)
- `stage_name` (string, default: "dev")
- `tags` (map)

**Outputs:**
- `lambda_function_name`, `lambda_role_arn`
- `api_url`
- `s3_bucket_id`, `s3_bucket_arn`

### Module: `notification`

**Purpose:** Deploys SNS topic and email subscription for alarm notifications

**Resources:**
- `aws_sns_topic` (devops-agent-alerts)
- `aws_sns_topic_subscription` (email protocol)

**Key Configuration:**
```hcl
resource "aws_sns_topic" "alerts" {
  name = "devops-agent-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```

**Inputs:**
- `alert_email` (string, required)
- `tags` (map)

**Outputs:**
- `sns_topic_arn`

### Module: `observability`

**Purpose:** Deploys CloudWatch alarms and log metric filters

**Resources:**
- `aws_cloudwatch_metric_alarm` (errors)
- `aws_cloudwatch_metric_alarm` (duration)
- `aws_cloudwatch_log_metric_filter` (ERROR pattern)

**Key Configuration:**
```hcl
# Error Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "lambda-errors-${var.lambda_function_name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
}

# Duration Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  # Similar structure, p99 > 5000ms
}

# Log Metric Filter
resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "lambda-error-filter"
  log_group_name = "/aws/lambda/${var.lambda_function_name}"
  pattern        = "ERROR"
  # ... metric transformation
}
```

**Inputs:**
- `lambda_function_name` (string, from app_stack)
- `sns_topic_arn` (string, from notification)
- `tags` (map)

**Outputs:**
- `error_alarm_arn`, `duration_alarm_arn`

### Root Module Wiring

**File:** `terraform/main.tf`

```hcl
module "app_stack" {
  source = "./modules/app_stack"
  aws_region  = var.aws_region
  stage_name  = var.stage_name
  tags        = local.default_tags
}

module "notification" {
  source      = "./modules/notification"
  alert_email = var.alert_email
  tags        = local.default_tags
}

module "observability" {
  source               = "./modules/observability"
  lambda_function_name = module.app_stack.lambda_function_name
  sns_topic_arn        = module.notification.sns_topic_arn
  tags                 = local.default_tags
}
```

**Dependencies:**
- `app_stack` has no dependencies (deployed first)
- `notification` has no dependencies (deployed first)
- `observability` depends on outputs from both `app_stack` and `notification`

### Backend Configuration

**File:** `terraform/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-backend-demo-ue1"  # Overridden by -backend-config in CI/CD
    key            = "devops-agent-demo/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true  # S3-native locking (Terraform >= 1.10)
  }
}
```

**Why S3-native locking?**
- Terraform 1.10+ supports native S3 locking (no DynamoDB table needed)
- Simpler setup (one less resource to manage)
- Lower cost (no DynamoDB charges)

**CI/CD Override:**
```bash
terraform init -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}"
```

Allows different buckets per environment without changing code.

---

## X-Ray Instrumentation

### Powertools for AWS Lambda (TypeScript)

**Why Powertools?**
- AWS-recommended toolkit for Lambda best practices
- Opinionated wrapper around X-Ray SDK
- Auto-captures cold starts, annotations, HTTP calls
- First-class Middy middleware support

**Dependencies:**
```json
{
  "@aws-lambda-powertools/tracer": "^2.30.1",
  "@middy/core": "^7.0.0"
}
```

### Middleware Pattern (Middy)

**What is Middy?**
- Lightweight middleware engine for AWS Lambda
- Separates cross-cutting concerns (tracing, logging) from business logic
- Composable middleware pattern

**Implementation:**
```typescript
import { Tracer } from '@aws-lambda-powertools/tracer';
import { captureLambdaHandler } from '@aws-lambda-powertools/tracer/middleware';
import middy from '@middy/core';

const tracer = new Tracer({ serviceName: 'handle_messages' });

const lambdaHandler = async (event) => {
  // Business logic here
};

export const handler = middy(lambdaHandler)
  .use(captureLambdaHandler(tracer));
```

**What `captureLambdaHandler` does:**
- Creates X-Ray subsegment for handler execution
- Captures cold-start annotations
- Captures response/error metadata
- Closes subsegment automatically

### S3 Client Instrumentation

**Automatic capture:**
```typescript
import { S3Client } from '@aws-sdk/client-s3';

const s3 = tracer.captureAWSv3Client(new S3Client({}));
```

**Effect:**
- Wraps all S3 API calls with X-Ray subsegments
- Captures request/response metadata
- Captures errors (including `AccessDenied`)

### Custom Subsegments

**Why custom subsegments?**
- Provides granular visibility into specific operations
- Makes it easier to identify which S3 call failed
- Demonstrates advanced X-Ray usage

**Implementation:**
```typescript
const subsegment = tracer.provider.getSegment()!.addNewSubsegment('S3-PutObject');
try {
  await s3.send(new PutObjectCommand(params));
  subsegment.close();
} catch (err) {
  subsegment.addError(err as Error);
  subsegment.close();
  throw err;
}
```

**Trace hierarchy:**
```
API Gateway Request
└── Lambda: handle_messages
    ├── Cold Start (automatic)
    ├── S3-ListObjects (custom subsegment)
    │   └── ListObjectsV2 (automatic via captureAWSv3Client)
    └── S3-PutObject (custom subsegment)
        └── PutObject (automatic via captureAWSv3Client)
```

### Build Configuration (esbuild)

**Key settings:**
```javascript
// build.js
esbuild.build({
  entryPoints: ['src/index.ts'],
  bundle: true,
  minify: true,
  platform: 'node',
  target: 'node24',
  external: [],  // Bundle everything, including AWS SDK
  outfile: 'dist/index.js',
});
```

**Why `external: []`?**
- Bundles AWS SDK v3 (not using Lambda's built-in version)
- ~1.7x faster cold starts ([AWS blog](https://aws.amazon.com/blogs/compute/optimizing-node-js-dependencies-in-aws-lambda/))
- Pinned SDK version (runtime SDK often outdated)
- Smaller effective bundle via tree-shaking

---

## Observability Strategy

### Three-Layer Monitoring

```
Layer 1: Metrics (CloudWatch Metrics)
  ↓ Aggregate health signals
Layer 2: Alarms (CloudWatch Alarms)
  ↓ Threshold-based alerting
Layer 3: Investigation (X-Ray + Logs + DevOps Agent)
  ↓ Root-cause analysis
```

### Metrics Layer

**Source:** AWS/Lambda namespace (automatic)

**Key Metrics:**
- `Errors` (count) — Lambda invocation errors
- `Duration` (milliseconds) — Lambda execution time
- `Invocations` (count) — Total invocations

**Evaluation Period:** 60 seconds (1 data point)

### Alarms Layer

**Error Alarm:**
- **Purpose:** Detect any Lambda errors
- **Threshold:** `Sum(Errors) >= 1` in 60s
- **Rationale:** Zero-tolerance for errors in demo (any error should alert)

**Duration Alarm:**
- **Purpose:** Detect slow Lambda executions
- **Threshold:** `p99(Duration) > 5000ms` in 60s
- **Rationale:** S3 operations should complete quickly; slow = possible issue

**Alarm Actions:**
- `alarm_actions`: SNS when alarm fires (OK → ALARM)
- `ok_actions`: SNS when alarm clears (ALARM → OK)

### Investigation Layer

**X-Ray Traces:**
- **Purpose:** Distributed tracing across API GW → Lambda → S3
- **Key Data:** Request/response times, error types, service map
- **DevOps Agent Use:** Identifies which component failed (S3 vs Lambda vs API GW)

**CloudWatch Logs:**
- **Purpose:** Detailed error messages and stack traces
- **Key Data:** Exception messages, `AccessDenied` details, request IDs
- **DevOps Agent Use:** Correlates error messages with X-Ray traces

**Log Metric Filter:**
- **Pattern:** `"ERROR"` (case-sensitive)
- **Purpose:** Creates a custom metric from log entries
- **Use Case:** Can trigger additional alarms or dashboards

### DevOps Agent Integration

**Resource Discovery:**
- Agent discovers resources via the connected AWS account's IAM role
- CloudWatch and X-Ray are built-in 1-way integrations (no additional setup needed)

**Telemetry Sources:**
- **CloudWatch** (built-in): Reads logs and metrics for error details
- **X-Ray** (built-in): Reads trace data to identify failed operations
- **GitHub** (connected): Reads recent commits to correlate code changes

**Investigation Flow:**
1. Alarm fires → Agent Space receives notification
2. Agent queries X-Ray for recent traces with errors
3. Agent identifies `AccessDenied` error on S3 operations
4. Agent queries CloudWatch Logs for detailed stack trace
5. Agent queries GitHub for recent S3-related changes
6. Agent produces RCA: "S3 bucket policy denies Lambda role access"
7. Agent suggests remediation: "Review bucket policy, restore Lambda permissions"

---

## Fault Injection Mechanism

### Concept

Demonstrates **infrastructure fault** (not code bug) — Lambda code is correct, but S3 bucket policy is misconfigured.

### Implementation: S3 Bucket Policy Modification

**Normal State:**
```json
{
  "Version": "2012-10-17",
  "Statement": []
}
```
(Empty policy = default permissions via IAM role work fine)

**Fault State:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FaultInjectionDeny",
      "Effect": "Deny",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/lambda-execution-role"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::messages-bucket-*",
        "arn:aws:s3:::messages-bucket-*/*"
      ]
    }
  ]
}
```

**Effect:**
- Explicit Deny overrides IAM role Allow
- Lambda receives `AccessDenied` on all S3 operations
- Error propagates to API Gateway (500 response)
- CloudWatch alarm fires within 60 seconds

### Script: `break_s3_policy.py`

**Purpose:** Injects the fault

**Process:**
1. Read current bucket policy via `get_bucket_policy()` (or `{}` if none)
2. Save original policy to `.original_policy_{bucket}.json`
3. Append `FaultInjectionDeny` statement to policy
4. Apply modified policy via `put_bucket_policy()`

**Inputs:**
- `--bucket-name` (from Terraform outputs)
- `--lambda-role-arn` (from Terraform outputs)

**Invocation (GitHub Actions):**
```bash
python scripts/break_s3_policy.py \
  --bucket-name messages-bucket-happy-noble-otter \
  --lambda-role-arn arn:aws:iam::123456789012:role/lambda-execution-role
```

### Script: `restore_s3_policy.py`

**Purpose:** Removes the fault

**Process:**
1. Check for saved policy file `.original_policy_{bucket}.json`
2. If file exists: restore via `put_bucket_policy()`
3. If no file: remove `FaultInjectionDeny` statement by Sid, or `delete_bucket_policy()` if it was the only statement

**Inputs:**
- `--bucket-name` (from Terraform outputs)

**Invocation:**
```bash
python scripts/restore_s3_policy.py \
  --bucket-name messages-bucket-happy-noble-otter
```

### Why Bucket Policy (not IAM)?

**Advantages:**
- **Reversible:** Easy to restore without re-deploying Lambda
- **Realistic:** Bucket policy misconfiguration is a common real-world issue
- **Demonstrable:** DevOps Agent can identify bucket policy as root cause (not code)
- **Safe:** Doesn't modify Lambda code or IAM roles

---

## Tagging Strategy

### Purpose of Tags

1. **Cost Tracking:** Group resources by `Project`
2. **IaC Identification:** `Terraform = true` warns against manual edits
3. **Environment Separation:** `Environment = dev` (if multi-env later)

### Default Tags (Terraform Provider)

**File:** `terraform/global_tags.tf`

```hcl
locals {
  default_tags = {
    Project     = "DevOpsAgentDemo"
    Terraform   = "true"
    Environment = var.stage_name
  }
}
```

**File:** `terraform/providers.tf`

```hcl
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.default_tags
  }
}
```

**Effect:**
- All resources created by Terraform automatically receive these tags
- No need to specify tags on individual resources

### Agent Space Configuration

DevOps Agent discovers resources via the connected AWS account's IAM role. **All AWS resources are auto-discovered** — no per-service configuration needed.

**AWS Resource Discovery (automatic):**
- CloudWatch, X-Ray, Lambda, SNS, S3, API Gateway — all discovered via AWS account connection
- No additional setup required for AWS services

**3rd Party Integrations (optional):**
- GitHub, Jira, PagerDuty, etc. require explicit configuration
- See [configuring capabilities for AWS DevOps Agent](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-capabilities-for-aws-devops-agent.html)

**Auto-Discovered Resources in This Demo:**
- Lambda function (handle_messages)
- API Gateway (HTTP v2)
- S3 bucket (messages-*)
- CloudWatch alarms (error, duration)
- SNS topic (devops-agent-alerts)
- CloudWatch log group (/aws/lambda/handle_messages_*)

---

## CI/CD Pipeline

### GitHub Actions Authentication (OIDC)

**Why OIDC?**
- No long-lived AWS access keys stored in GitHub
- Temporary credentials issued per workflow run
- Fine-grained permissions via IAM trust policy

**Trust Policy (IAM Role):**
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:nirgluzman/aws-devops-agent:ref:refs/heads/main",
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    }
  }
}
```

**Workflow Authentication:**
```yaml
- uses: aws-actions/configure-aws-credentials@v5
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION }}
```

### Workflow: `deploy-app.yml` (Unified)

**Trigger:** Push to `main` (path-filtered: `backend/**`, `terraform/modules/**`, `terraform/main.tf`) or manual (`workflow_dispatch`)

**Steps:**
1. Checkout code
2. Setup Node.js 24
3. Build & package Lambda: `npm ci && npm run build && zip -r ../../../terraform/lambda.zip dist/index.js package.json`
4. Configure AWS credentials (OIDC)
5. Terraform init (with backend-config override)
6. Terraform apply (auto-approve, passes `alert_email` variable)

**Deploys all modules** (app_stack + observability + notification) in a single run since they share one Terraform state.

**Why separate build + zip step?**
- Pre-built zip avoids Terraform Lambda module hash drift during apply
- Ensures consistent build environment (GitHub Actions runner)
- Faster apply (no build wait time)

### Workflow: `inject-fault.yml`

**Trigger:** Manual (`workflow_dispatch`) with inputs

**Inputs:**
- `bucket_name` (string, required)
- `lambda_role_arn` (string, required)

**Steps:**
1. Checkout code
2. Setup Python 3.12
3. Install boto3
4. Configure AWS credentials (OIDC)
5. Run `break_s3_policy.py` with inputs

**Security Note:**
- Uses same IAM role as deploy workflows
- Role needs `s3:PutBucketPolicy` permission

### Workflow: `destroy-all.yml`

**Trigger:** Manual (`workflow_dispatch`)

**Steps:**
1. Checkout code
2. Configure AWS credentials (OIDC)
3. Terraform init
4. Terraform destroy (auto-approve)

**Why auto-approve?**
- Demo environment, not production
- Manual trigger already serves as confirmation
- Avoids interactive prompt in CI/CD

**Cleanup Behavior:**
- S3 buckets: `force_destroy = true` (auto-empties)
- State file: Remains in state bucket (safe)
- CloudWatch log groups: May persist (check retention)

---

## Technical Decisions

### Why HTTP API (not REST API)?

**Advantages:**
- 71% cheaper ($1/million vs $3.50/million requests)
- Lower latency (native AWS_PROXY support)
- Simpler configuration (fewer options to configure)

**Trade-offs:**
- Fewer features (no API keys, request validation, caching)
- Acceptable for demo (proxy use case, no advanced features needed)

### Why Bundle AWS SDK v3?

**AWS Recommendation:** [Optimizing Node.js dependencies in AWS Lambda](https://aws.amazon.com/blogs/compute/optimizing-node-js-dependencies-in-aws-lambda/)

**Benefits:**
- **~1.7x faster cold starts** (smaller effective bundle via tree-shaking)
- **Pinned SDK version** (runtime SDK often outdated/unpatched)
- **Smaller bundle** (only imported modules, not entire SDK)

**Build Config:**
```javascript
esbuild.build({
  external: [],  // Bundle everything
  bundle: true,
  minify: true,
});
```

### Why Powertools (not raw X-Ray SDK)?

**Advantages:**
- AWS-recommended toolkit (official best practices)
- Auto-captures cold starts, annotations, HTTP calls
- Middy middleware = clean separation of concerns
- Better TypeScript support
- Less boilerplate code

**Comparison:**
```typescript
// Raw X-Ray SDK (verbose)
const segment = AWSXRay.getSegment();
const subsegment = segment.addNewSubsegment('operation');
AWSXRay.setSegment(subsegment);
try {
  // ... operation
} finally {
  AWSXRay.setSegment(subsegment.parent);
  subsegment.close();
}

// Powertools (cleaner)
const subsegment = tracer.getSegment()?.addNewSubsegment('operation');
tracer.setSegment(subsegment);
// ... operation
tracer.setSegment(subsegment?.getParent());
subsegment?.close();
```

### Why Middy Middleware?

**Advantages:**
- Separates cross-cutting concerns (tracing, logging) from business logic
- Composable (can stack multiple middleware)
- Powertools provides first-class Middy support

**Pattern:**
```typescript
export const handler = middy(lambdaHandler)
  .use(captureLambdaHandler(tracer))
  .use(injectLambdaContext(logger))  // Can add more middleware
  .use(errorHandler());
```

### Why S3-Native Locking (not DynamoDB)?

**Terraform 1.10+ Feature:** S3-native state locking

**Advantages:**
- Simpler setup (one less resource to manage)
- Lower cost (no DynamoDB table charges)
- Same reliability (S3 conditional writes)

**Configuration:**
```hcl
terraform {
  backend "s3" {
    use_lockfile = true  # Enables S3-native locking
  }
}
```

### Why `force_destroy = true` on S3?

**Demo Convenience:**
- Allows `terraform destroy` without manual bucket emptying
- Avoids "bucket not empty" errors

**Production Warning:**
- **Never use in production** (data loss risk)
- Use bucket lifecycle policies + manual verification instead

### Why Explicit Deny (not Remove IAM Policy)?

**Advantages:**
- **Demonstrates bucket policy misconfiguration** (realistic scenario)
- **Easier to restore** (remove Deny statement, don't recreate IAM policy)
- **Explicit Deny overrides IAM Allow** (demonstrates AWS policy evaluation order)
- **Agent can identify bucket policy as root cause** (not IAM role issue)

**Policy Evaluation Order:**
1. Explicit Deny (highest precedence)
2. Explicit Allow
3. Implicit Deny (default)

---

## Summary

This architecture demonstrates:
- **Serverless best practices:** HTTP API, Lambda with Powertools, S3 storage
- **Observability:** X-Ray tracing, CloudWatch alarms, SNS notifications
- **Infrastructure as Code:** Modular Terraform, S3 remote state, CI/CD automation
- **Fault injection:** Realistic S3 policy misconfiguration
- **DevOps Agent:** Autonomous RCA via trace/log correlation

**Key Insight:** The demo proves that AWS DevOps Agent can differentiate between **code bugs** (Lambda logic) and **infrastructure misconfigurations** (S3 bucket policy), providing accurate root-cause analysis.
