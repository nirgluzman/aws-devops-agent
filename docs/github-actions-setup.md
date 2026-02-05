# GitHub Actions Configuration

Complete setup guide for GitHub Actions CI/CD workflows with AWS OIDC authentication.

---

## Repository Secrets & Variables

Configure under *Settings → Secrets and variables → Actions* (repository level):

| Name | Type | Level | Example value | Used by |
|------|------|-------|---------------|---------|
| `AWS_ROLE_ARN` | **Secret** | Repository | `arn:aws:iam::123456789012:role/github-actions-terraform` | All workflows — OIDC role assumption |
| `AWS_REGION` | **Variable** | Repository | `us-east-1` | All workflows — `aws-region` + Terraform provider |
| `ALERT_EMAIL` | **Variable** | Repository | `ops-team@example.com` | Deploy workflows — `-var alert_email` |
| `TF_STATE_BUCKET` | **Variable** | Repository | `terraform-backend-demo-ue1` | Deploy/destroy — backend config consistency |

---

## AWS IAM OIDC Configuration

### OIDC Provider Setup

Create an OIDC identity provider in AWS IAM:

1. **Provider URL:** `https://token.actions.githubusercontent.com`
2. **Audience:** `sts.amazonaws.com`
3. **Thumbprint:** (automatically fetched by AWS)

### IAM Role Trust Relationship

The GitHub Actions role must have the following trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::447648295726:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:nirgluzman/aws-devops-agent:ref:refs/heads/main"
          ]
        }
      }
    }
  ]
}
```

**Key conditions:**
- `token.actions.githubusercontent.com:aud`: Validates the token audience is AWS STS
- `token.actions.githubusercontent.com:sub`: Restricts to specific repository and branch (`main`)

### Required IAM Permissions

The role should have policies granting:
- Terraform operations (create/update/delete AWS resources)
- S3 backend access (`terraform-backend-demo-ue1` bucket)
- CloudWatch, X-Ray, IAM, Lambda, API Gateway, SNS permissions

**Recommendation:** Use `AdministratorAccess` for demo/dev, scope down for production.

---

## Workflow Configuration

### Available Workflows

1. **Deploy** (`.github/workflows/deploy-app.yml`)
   - Unified pipeline: builds Lambda + applies all Terraform modules
   - Triggers on push to `main` (path-filtered) or manual dispatch
   - Deploys API Gateway + Lambda + S3 + CloudWatch alarms + SNS

2. **Smoke Test** (`.github/workflows/smoke-test.yml`)
   - Validates API health (GET/POST endpoints)
   - Input: `api_url`

3. **Inject Fault** (`.github/workflows/inject-fault.yml`)
   - Runs Python script to modify S3 bucket policy
   - Inputs: `bucket_name`, `lambda_role_arn`

4. **Destroy All Infrastructure** (`.github/workflows/destroy-all.yml`)
   - Runs `terraform destroy -auto-approve`
   - Cleans up all Terraform-managed resources

### Manual Workflow Dispatch

All workflows use `workflow_dispatch` for manual triggering:

```yaml
on:
  workflow_dispatch:
    inputs:
      bucket_name:
        description: 'S3 bucket name'
        required: true
```

Trigger via: *Actions → [Workflow Name] → Run workflow*

---

## Troubleshooting

### OIDC Authentication Fails

**Error:** `Error: Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Solution:**
1. Verify OIDC provider exists in AWS IAM
2. Check trust policy `sub` condition matches repository format: `repo:OWNER/REPO:ref:refs/heads/BRANCH`
3. Confirm `AWS_ROLE_ARN` secret is set correctly

### Terraform State Access Denied

**Error:** `Error: Failed to get existing workspaces: AccessDenied`

**Solution:**
1. Verify `TF_STATE_BUCKET` variable matches actual backend bucket name
2. Check IAM role has `s3:ListBucket`, `s3:GetObject`, `s3:PutObject` on state bucket
3. Confirm backend configuration in `terraform/backend.tf` uses correct bucket

### Workflow Uses Wrong Region

**Error:** Resources created in wrong AWS region

**Solution:**
1. Verify `AWS_REGION` repository variable is set to `us-east-1`
2. Check workflow YAML uses `${{ vars.AWS_REGION }}`
3. Confirm Terraform provider configuration references correct region

---

## Security Best Practices

1. **Least Privilege:** Scope IAM role permissions to minimum required (avoid `*` actions)
2. **Branch Protection:** Restrict workflows to run only on `main` branch via trust policy `sub` condition
3. **Secret Rotation:** Periodically rotate OIDC role credentials and update trust policies
4. **Audit Logs:** Enable CloudTrail to monitor GitHub Actions role assumption events
5. **State Encryption:** Ensure S3 backend bucket has SSE-S3 or SSE-KMS enabled

---

## References

- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
