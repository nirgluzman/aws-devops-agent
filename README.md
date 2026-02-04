# AWS DevOps Agent Demo

Serverless message API that demonstrates **AWS DevOps Agent** autonomously diagnosing infrastructure faults via X-Ray traces and CloudWatch logs.

## Architecture

```
API Gateway (HTTP v2, /dev)
  ├── GET  /messages
  ├── POST /messages
  └── AWS_PROXY ──→ Lambda (Node.js 24.x, TypeScript)
                        ├── S3 (store/list JSON messages)
                        ├── X-Ray tracing (Powertools Tracer)
                        └── CloudWatch Logs (1-day retention)

CloudWatch Alarms ──→ SNS Topic ──→ Email Notification
                          ↓
                    DevOps Agent (Agent Space)
                        ├── X-Ray traces      ── root-cause analysis
                        ├── CloudWatch Logs   ── error correlation
                        ├── GitHub commits    ── change correlation
                        └── Produces RCA + actionable remediation
```

## How It Works

1. **Deploy** a healthy serverless message API
2. **Inject fault** — deny S3 access via bucket policy
3. **Observe** — CloudWatch alarm fires, SNS notifies
4. **DevOps Agent** picks up the incident, correlates X-Ray + CloudWatch + GitHub, produces root-cause analysis
5. **Restore** — remove the faulty policy, verify recovery

## Tech Stack

- **Lambda:** TypeScript, esbuild, AWS SDK v3, Powertools Tracer
- **IaC:** Terraform (AWS provider ~6.0, `terraform-aws-modules`)
- **Observability:** X-Ray, CloudWatch Alarms, SNS
- **Fault Injection:** Python 3.12 (boto3)
- **CI/CD:** GitHub Actions (OIDC auth)

## Project Structure

```
├── backend/functions/handle_messages/   # Lambda handler (TypeScript)
├── terraform/                           # Root Terraform config
│   └── modules/
│       ├── app_stack/                   # API GW + Lambda + S3
│       ├── observability/               # CloudWatch Alarms + Log Filters
│       └── notification/                # SNS Topic + Email
├── scripts/                             # Fault injection (Python)
├── .github/workflows/                   # CI/CD pipelines
└── docs/                                # Specs and guides
```

## Prerequisites

- AWS account with Lambda, API Gateway, S3, CloudWatch, X-Ray, SNS, IAM permissions
- [AWS DevOps Agent](https://aws.amazon.com/devops-agent/) preview access
- S3 state bucket `terraform-backend-demo-ue1` in us-east-1 (versioning enabled, SSE-S3)
- GitHub OIDC provider configured (IAM role stored as `AWS_ROLE_ARN` secret)
- Node.js 24.x, Python 3.12, Terraform >= 1.10

## AWS Region

The DevOps Agent **service** (Agent Spaces, console) runs exclusively in US East (N. Virginia). However, it can monitor and investigate resources in **any region** via cross-region IAM role access.

We deploy **all demo infrastructure** to `us-east-1` as well - not because it's required, but to keep the demo simple (single region, no cross-region latency or IAM complexity).
