# AWS DevOps Agent Demo - Step-by-Step Runbook

This guide walks through deploying the demo infrastructure, injecting a fault, and observing AWS DevOps Agent diagnose the root cause.

---

## Prerequisites

Before starting, ensure you have:

1. **AWS Account Setup**
   - S3 state bucket `terraform-backend-demo-ue1` in `us-east-1` (versioning enabled, ACLs disabled, SSE-S3)
     - **Note:** Bucket name must be globally unique
   - [GitHub OIDC provider configured for AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
   - IAM role with `AdministratorAccess` (or scoped permissions for Terraform)
   - Tags on both: `Project=DevOpsAgentDemo`

2. **GitHub Setup**

   Configure under *Settings → Secrets and variables → Actions* (repository level):

   | Name | Type | Level | Example value | Used by |
   |------|------|-------|---------------|---------|
   | `AWS_ROLE_ARN` | **Secret** | Repository | `arn:aws:iam::123456789012:role/github-actions-terraform` | All workflows — OIDC role assumption |
   | `AWS_REGION` | **Variable** | Repository | `us-east-1` | All workflows — `aws-region` + Terraform provider |
   | `ALERT_EMAIL` | **Variable** | Repository | `ops-team@example.com` | Deploy workflows — `-var alert_email` |
   | `TF_STATE_BUCKET` | **Variable** | Repository | `terraform-backend-demo-ue1` | Deploy/destroy — backend config consistency |

3. **AWS DevOps Agent Access**
   - Preview access to AWS DevOps Agent (https://aws.amazon.com/devops-agent/)
   - Agent Space created in us-east-1

---

## Step 1: Deploy the Infrastructure

Deploy via GitHub Actions using manual workflow trigger:

1. Go to **Actions → Deploy**
2. Click **Run workflow** → select `main` branch → **Run workflow**
3. Workflow executes (unified pipeline):
   - Builds Lambda function (Node.js 24)
   - Runs `terraform init` + `terraform apply`
   - Deploys all modules: API Gateway + Lambda + S3 + CloudWatch alarms + SNS
4. Deployment completes in ~3 minutes

**Note:** All modules share one Terraform state, so they're deployed in a single unified workflow to prevent source_code_hash mismatches.

### Retrieve Outputs

After the workflow completes:

1. Go to **Actions → Deploy → latest run → Terraform Apply step**
2. Scroll to bottom of logs for Terraform outputs:
   - `api_url` — e.g., `https://abc123.execute-api.us-east-1.amazonaws.com/dev`
   - `lambda_function_name` — e.g., `handle_messages_xyz`
   - `lambda_role_arn` — e.g., `arn:aws:iam::123456789012:role/lambda_execution_role_xyz`
   - `s3_bucket_id` — e.g., `messages-bucket-xyz`
   - `sns_topic_arn` — e.g., `arn:aws:sns:us-east-1:123456789012:devops-agent-alerts`
   - `error_alarm_arn` — e.g., `arn:aws:cloudwatch:us-east-1:123456789012:alarm:lambda-errors-handle_messages_xyz`
   - `duration_alarm_arn` — e.g., `arn:aws:cloudwatch:us-east-1:123456789012:alarm:lambda-duration-handle_messages_xyz`

**Save these values** — you'll need them for fault injection.

---

## Step 2: Smoke Test

Run the automated smoke test to validate the API is healthy before proceeding:

```bash
bash scripts/smoke-test.sh "https://abc123.execute-api.us-east-1.amazonaws.com/dev"
```

Or trigger via **Actions → Smoke Test → Run workflow** (provide `api_url`).

The script tests:
1. `GET /messages` — asserts HTTP 200
2. `POST /messages` with a test payload — asserts HTTP 200
3. `GET /messages` — asserts the posted message appears in response

All tests must pass before continuing.

---


### Health Check: API Endpoints

**Option 1: cURL**

Test that the API is working:

```bash
# GET /messages (should return empty array)
curl -X GET "https://abc123.execute-api.us-east-1.amazonaws.com/dev/messages"
# Expected: 200 OK, body: []

# POST /messages (create a message)
curl -X POST "https://abc123.execute-api.us-east-1.amazonaws.com/dev/messages" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, DevOps Agent!"}'
# Expected: 200 OK, body: {"message":"Hello, DevOps Agent!","timestamp":"2025-02-04T..."}

# GET /messages (should return the posted message)
curl -X GET "https://abc123.execute-api.us-east-1.amazonaws.com/dev/messages"
# Expected: 200 OK, body: [{"message":"Hello, DevOps Agent!","timestamp":"2025-02-04T..."}]
```

**Option 2: HTTP Client (VS Code)**

Use the `terraform/test.http` file with a REST client extension:
1. Open `terraform/test.http` in VS Code
2. Update `@baseUrl` with your API endpoint (from Step 1 outputs)
3. Click "Send Request" above each request to execute
4. View responses in the side panel

### Verify X-Ray Tracing

1. Open [AWS X-Ray Console](https://console.aws.amazon.com/xray/home?region=us-east-1#/service-map)
2. Look for service map showing:
   - **API Gateway** (entry point)
   - **Lambda** (handle_messages)
   - **S3** (messages bucket)
3. Click on **Lambda** segment → **Subsegments**
   - Verify custom subsegments: `S3-ListObjects`, `S3-PutObject`
   - Confirm proper nesting and timing

### Confirm SNS Subscription

1. Check your email inbox for AWS Notification from SNS
2. Subject: "AWS Notification - Subscription Confirmation"
3. Click **Confirm subscription** link
4. Status should change from `PendingConfirmation` → `Subscribed`

---

## Step 3: Configure DevOps Agent Space (Agent Space)

1. Open [AWS DevOps Agent Console](https://console.aws.amazon.com/devops-agent/home?region=us-east-1)
2. Create a new **Agent Space** (or select existing)
3. Connect your **AWS account**:
   - **Auto-discovers** AWS resources: Lambda, SNS, S3, API Gateway, CloudWatch, X-Ray
   - **No additional setup** needed for AWS services
4. **(Recommended) Connect Slack or ServiceNow** for automated investigation notifications:
   - **Without Slack/ServiceNow**: Investigation results only visible in Agent Space UI (manual check required)
   - **With Slack/ServiceNow**: Automatically receive RCA findings and remediation steps in your team channel/tickets
   - **Note**: Email/SNS do not support investigation result notifications (only CloudWatch alarm status)
   - See [capabilities configuration guide](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-capabilities-for-aws-devops-agent.html)
5. (Optional) Connect **GitHub** repository (for change correlation)
6. Save Agent Space configuration

---

## Step 4: Inject Fault

Now inject a deliberate S3 bucket policy failure to trigger the alarm.

1. Go to **Actions → Inject Fault**
2. Click **Run workflow**
3. Provide inputs:
   - `bucket_name`: `<s3_bucket_id>` from Step 1 outputs
   - `lambda_role_arn`: `<lambda_role_arn>` from Step 1 outputs
4. Click **Run workflow**
5. Wait for workflow to complete (~30 seconds)

**Result:** S3 bucket policy now has a `Deny` statement for `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` targeting the Lambda role.

---

## Step 5: Observe the Fault

### Watch the API Fail

Trigger **Actions → Smoke Test → Run workflow** (provide `api_url`).

The workflow will fail - confirming the fault is active and the API returns `500 Internal Server Error`.

### Monitor CloudWatch

1. Open [CloudWatch Alarms Console](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:)
2. Look for:
   - **Error Alarm** (Lambda errors >= 1, 60s period)
   - **Duration Alarm** (Lambda p99 > 5000ms, 60s period)
3. Status should change from `OK` → `ALARM` within 60-90 seconds
4. Check alarm actions: should trigger SNS notification

### Check SNS Notification

1. Check email inbox for SNS alarm notification
2. Includes alarm name, threshold, current metric value
3. Confirms observability pipeline is working

### Check X-Ray Traces

1. [X-Ray Console](https://console.aws.amazon.com/xray/home?region=us-east-1#/service-map)
2. Filter on failed traces (errors)
3. Expand Lambda segment
4. View error details: `AccessDenied` from S3
5. Custom subsegments show where failure occurred

### Check CloudWatch Logs

1. Open [CloudWatch Logs](https://console.aws.amazon.com/logs/home?region=us-east-1)
2. Find log group: `/aws/lambda/handle_messages_*`
3. View recent logs:
   - Lambda function error traces
   - S3 AccessDenied exceptions
   - Stack traces showing S3 operation failure

---

## Step 6: DevOps Agent Diagnosis

Now let the **AWS DevOps Agent** analyze the fault:

1. Go to your **Agent Space** (from Step 3)
2. Agent should automatically detect the alarm + errors
3. Agent correlates:
   - **CloudWatch Alarms** (error rate spike)
   - **X-Ray Traces** (S3 AccessDenied errors)
   - **CloudWatch Logs** (error messages)
   - **GitHub Commits** (recent changes, if configured)
4. Agent produces **Root Cause Analysis (RCA):**
   - Identifies S3 access failure
   - Correlates to Lambda role denial
   - Links to recent policy changes (if in Git history)
5. Agent suggests **Remediation:**
   - Review and update S3 bucket policy
   - Restore Lambda role S3 permissions
   - Example: "Restore S3 permissions to IAM role via bucket policy"

---

**💡 Getting Automated Notifications:**

**Current demo setup:**
- ✅ CloudWatch alarm → SNS → **Email** (alarm status only)
- ❌ DevOps Agent RCA → Email (not supported)

**To receive investigation results automatically:**
1. **Integrate Slack** (recommended):
   - Agent Space → Settings → Integrations → Slack
   - Investigation findings posted directly to Slack channel
2. **Integrate ServiceNow** (alternative):
   - Agent Space → Settings → Integrations → ServiceNow
   - RCA findings added to incident tickets

**Without Slack/ServiceNow:** You must manually check Agent Space UI for investigation details — email/SNS do not support RCA notification delivery.

---

## Step 7: Restore Infrastructure

Once you've observed the fault and reviewed the RCA, restore normal operation.

**Restore via script:**

```bash
python scripts/restore_s3_policy.py --bucket-name <s3_bucket_id>
```

**Or manually via AWS Console:**

1. Open [S3 Console](https://s3.console.aws.amazon.com/s3/buckets)
2. Select your bucket (`<s3_bucket_id>`)
3. Go to **Permissions → Bucket policy**
4. Remove the `FaultInjectionDeny` statement (Sid)
5. Save changes

**Result:** S3 bucket policy is restored to original state. Lambda regains S3 access.

### Verify Recovery

1. Make API requests — should succeed again:
   ```bash
   curl -X POST "https://abc123.execute-api.us-east-1.amazonaws.com/dev/messages" \
     -H "Content-Type: application/json" \
     -d '{"message": "Back to normal!"}'
   # Expected: 200 OK
   ```

2. CloudWatch alarms should return to `OK` status within 60-90 seconds

3. X-Ray traces should show successful S3 operations

---

## Step 8: Teardown

When done, clean up all resources to avoid incurring costs.

1. Go to **Actions → Destroy All Infrastructure**
2. Click **Run workflow** → select `main` branch
3. Confirm by clicking **Run workflow**
4. Workflow runs `terraform destroy -auto-approve`
5. Resources are destroyed in ~2 minutes

**Remaining Resources (manual cleanup if desired):**
- S3 state bucket (`terraform-backend-demo-ue1`) — retain for state history or delete manually
- GitHub OIDC provider — retain for future use or delete manually
- CloudWatch Log Groups — may be retained (check retention settings)

---

## Troubleshooting

### Terraform Apply Fails (Permissions)

**Problem:** IAM role lacks permissions

**Solution:** Verify GitHub OIDC trust policy:
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

### SNS Notifications Not Arriving

**Problem:** Email subscription stuck in `PendingConfirmation`

**Solution:** Check email inbox (including spam) for AWS confirmation email. Click **Confirm subscription** link.

### X-Ray Traces Not Appearing

**Problem:** Lambda traces not visible in X-Ray

**Solution:** Verify:
1. Lambda IAM role has `xray:PutTraceSegments`, `xray:PutTelemetryRecords`
2. Lambda code imports and uses Tracer (check `src/index.ts`)
3. X-Ray tracing enabled: check Lambda configuration for `Tracing: Active`

### DevOps Agent Not Detecting Fault

**Problem:** Agent Space shows no recent incidents

**Solution:**
1. Verify Agent Space is subscribed to CloudWatch + X-Ray
2. Check Agent Space logs/activity
3. Manually trigger API failure to ensure alarms fire
4. Wait ~2 minutes for alarm → SNS → Agent pickup

---

## Additional Resources

- [AWS X-Ray Documentation](https://docs.aws.amazon.com/xray/)
- [AWS Lambda Powertools](https://docs.aws.amazon.com/lambda/latest/dg/lambda-powertools.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS DevOps Agent (Preview)](https://aws.amazon.com/devops-agent/)
