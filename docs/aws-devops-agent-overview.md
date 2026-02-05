# [AWS DevOps Agent (Preview)](https://aws.amazon.com/devops-agent/)

## Overview

The **AWS DevOps Agent** is a frontier AI agent designed to drive operational excellence by resolving and proactively preventing incidents. It functions as an **always-on, autonomous on-call engineer**, accelerating incident resolution (**MTTR**) by correlating telemetry, code changes, and deployment data across your entire operational toolchain.
It systematically analyzes past incidents and operational patterns to prevent future issues.

## Core Architectural Concepts

### Agent Spaces and Isolation
-   **Agent Spaces** are the primary security boundaries, acting as independent logical containers that define the tools and infrastructure the agent can access. Each Agent Space operates independently with its own configurations, permissions, and connections to external systems.
-   This architecture enforces **strict isolation** to ensure security and prevent unintended access across different environments (e.g., Production) or teams.
-   The service uses a **dual-console architecture**: the AWS Management Console for administrative setup and management, and the dedicated **DevOps Agent Web App** for operational activities like investigations and reviewing recommendations.

### Regional Processing and Data Flow
-   **Primary Region:** The service operates from the **US East (N. Virginia) region (us-east-1)**, which serves as the primary processing hub and data storage location.
-   **Cross-Region Inference:** To optimize compute resources and model availability, inputs, requests, and output may be processed in other US regions via Amazon Bedrock, but customer data remains stored in US East (N. Virginia).
-   **Data Security:** All customer data (logs, metrics, knowledge items, etc.) is encrypted **at rest** using AWS-managed keys and encrypted **in transit** across the agent's private network and to outside networks.
-   **PII Responsibility:** The AWS DevOps Agent **does not filter PII** (Personally Identifiable Information) when summarizing data gathered during investigations or chat responses. Customers are responsible for redacting PII before storing it in integrated observability logs and data sources.

## Security and Access Management

### Prompt Injection Protection
The agent utilizes multiple layers of defense against prompt injection attacks, where malicious instructions are embedded in external data sources like logs or resource tags:
-   **Limited Write Capabilities:** The agent's tools are restricted from modifying or deleting infrastructure or applications, with the exception of opening tickets and support cases.
-   **Immutable Audit Trail (Agent Journal):** The Agent Journal logs every reasoning step, action taken, and chat message, and these entries cannot be modified once recorded, minimizing the risk of an attack hiding its actions.
-   **AI Safety Protections:** The agent uses Claude Sonnet 4.5, which includes **AI Safety Level 3 (ASL-3)** protections to detect and prevent prompt injection attacks.
-   **Account Boundary Enforcement:** The agent operates only within the scope permitted by the IAM roles assigned to it in the primary and secondary AWS accounts.

### IAM and Access Control
-   **Least Privilege:** All three required IAM roles (Primary account role, Secondary account roles, and Web app role) must adhere to the **principle of least privilege**, granting only the necessary **read-only permissions** required for investigations.
-   **IAM Enforcement:** IAM policies are the *only* way to truly limit the agent's access to AWS service APIs and resources, enabling restriction by specific AWS services, resource ARN patterns, tags, or region constraints (using the `aws:RequestedRegion` condition key).
-   **Authentication:**
    -   **IAM Identity Center integration:** Recommended for production, providing centralized user management, federation with external identity providers, and configurable session durations up to 12 hours.
    -   **IAM authentication link:** Used for initial setup or administrative access, with sessions limited to 30 minutes.
-   **Custom Tool Risk:** Custom **Model Context Protocol (MCP) servers** introduce additional prompt injection risk. They must be carefully reviewed and restricted to performing **read-only actions** to mitigate this risk.

### Public Preview Status
-   **Compliance:** During the public preview, the service is **not compliant** with standards such as SOC 2, PCI-DSS, ISO 27001, or FedRAMP.
-   **Pricing and Quotas:** Usage is complimentary during the preview, but customers may incur charges from integrated AWS or non-AWS services for queries. Limits include a maximum of **10 Agent Spaces**, **20 incident resolution hours** per month, and a maximum of **three concurrent incident resolution investigation tasks**.

## Operational Capabilities and Incident Response

-   **Response Initiation:** Investigations can be triggered automatically via built-in integrations (like ServiceNow tickets), **webhooks** (from systems like PagerDuty or Grafana alarms), or manually from the Web App.
-   **Root Cause Analysis:** The agent correlates data to identify the root cause, and if it encounters missing data or permissions, it reports these as **Investigation Gaps**.
-   **Mitigation Plans:** The agent generates mitigation plans upon root cause determination, which include Prepare, Pre-Validate, Apply, and Post-Validate steps. These plans may provide "agent-ready specs" for use with coding agents.
-   **Proactive Prevention:** The Prevention feature delivers **Targeted Recommendations** weekly (or manually triggered) based on historical patterns to strengthen four key areas: **Observability posture, Testing gaps (deployment pipeline enhancement), Code changes (application resilience), and Infrastructure architecture**.
-   **Human Support:** Users with an eligible support plan can create an **AWS Support case** directly from an investigation in the Web App, which automatically shares the investigation timeline, resource information, observability data, and recent changes with AWS Support experts.

## Notifications and Alerting Integration

### How DevOps Agent Handles Notifications

**IMPORTANT:** AWS DevOps Agent does **NOT** natively send RCA findings via SNS, email, or other push notification channels.

#### Inbound Triggers (How Agent Receives Alerts)

The agent **receives** triggers from various alerting systems to initiate investigations:
- **CloudWatch Alarms** — Metric breaches trigger automatic investigations
- **SNS Notifications** — Can be configured as webhook triggers
- **ServiceNow Tickets** — Built-in bidirectional integration
- **PagerDuty Incidents** — Via webhook integration
- **Custom Webhooks** — From tools like Grafana, Prometheus (via MCP server)

#### Outbound Findings Delivery (How Agent Shares Results)

The agent **delivers** RCA findings and recommendations through:
- **Agent Space Web UI** (primary interface) — Interactive chat interface for viewing investigation timeline, root cause analysis, and mitigation plans
- **Collaboration Tools** — ServiceNow (bidirectional updates), Slack (outbound notifications)
- **AWS Support Cases** — Direct creation with full investigation context for faster resolution
- **MCP Server Integrations** — Custom tools, proprietary ticketing systems, specialized platforms

#### Architecture Pattern for This Demo

```
CloudWatch Alarm → SNS Topic → Email
      ↓                          ↓
   triggers                  Ops team receives
      ↓                      operational alert
DevOps Agent
      ↓
   performs RCA
      ↓
Agent Space UI + Slack/ServiceNow
      ↓
Ops team views detailed findings
```

**Key Distinction:** SNS emails contain **alarm state changes only** (ALARM/OK). Detailed root cause analysis, investigation timeline, and mitigation recommendations must be viewed in the **Agent Space Web UI** or integrated collaboration tools.

---

## Key Integrations

The agent integrates with various tools using specific security models:

| Category | Provider Examples | Integration Model | Key Security/Authentication |
| :--- | :--- | :--- | :--- |
| **Observability** | Dynatrace | Built-in, 2-way (Topology, Introspection, Status Updates) | OAuth Token |
| **Observability** | Amazon CloudWatch | Built-in, 1-way (Topology, Introspection) | IAM Role (requires no extra setup) [50] |
| **Observability/Ticketing** | Datadog, Splunk, New Relic | Built-in, 1-way (Webhook trigger, MCP Introspection) | Bearer Token, API Key |
| **CI/CD** | GitHub, GitLab | Two-step registration (Account-level registration + Agent Space connection) | OAuth (GitHub), Access Token (GitLab) |
| **Ticketing/Chat** | ServiceNow, Slack | ServiceNow is bidirectional; Slack is outbound | OAuth Client Key/Token, HMAC/Bearer Token |
| **Extensibility** | Custom Tools, Grafana, Prometheus | Model Context Protocol (MCP) Server | HTTPS, OAuth 2.0, API Key/Token |

### CI/CD Deployment Tracking
To enable the agent to track deployments and correlate them with incidents, registered CI/CD projects (GitHub/GitLab) must be configured to associate with specific AWS resource ARNs. This mapping bridges the gap between your code and infrastructure, allowing the agent to automatically determine if a recent deployment is the root cause of an issue.

Supported Associations:
- **CloudFormation stacks** / **AWS CDK deployments**
- **Amazon ECR repositories**
- **S3 object ARNs** for Terraform state files

Following this configuration, the agent will automatically begin tracking deployment artifacts in GitHub Actions and GitLab Pipelines, though it will not track artifacts deployed by external systems like Jenkins or ArgoCD.