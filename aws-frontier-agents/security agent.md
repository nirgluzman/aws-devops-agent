# [AWS Security Agent (Preview)](https://aws.amazon.com/security-agent/)

## Overview

AWS Security Agent is a **frontier AI agent** designed to proactively secure applications throughout the entire development lifecycle - from design to deployment. It automates security reviews based on your specific organizational requirements and provides context-aware, on-demand penetration testing.

*Note: This service is currently in **Preview** and available in the **US East (N. Virginia)** region.*


## Key Capabilities

* **Design Security Review**: Provides real-time feedback on architectural documents before a single line of code is written, ensuring compliance with security standards early on.
* **Code Security Review**: Automatically analyzes pull requests (PRs) for common vulnerabilities (e.g., SQL injection) and organizational policy violations, providing remediation guidance directly in GitHub.
* **On-Demand Penetration Testing**: Executes sophisticated, multi-step attack chains to discover and validate vulnerabilities in live apps. It goes beyond static scanning by analyzing source code to understand application context.

## Core Benefits

* **Shift-Left Security**: Identify and fix architectural flaws and coding errors early to reduce late-stage rework.
* **Automated Policy Enforcement**: Define security requirements (e.g., approved encryption libraries or logging standards) once in the AWS Console, and the agent enforces them globally.
* **Scalable Expertise**: Scales security reviews to match development velocity, transforming manual bottlenecks into on-demand automated tasks.
* **Actionable Remediation**: For confirmed vulnerabilities, the agent provides reproducible attack paths and creates **remediation pull requests** with ready-to-implement code fixes.

## How It Works

* **AWS Management Console**: Used by administrators to define security requirements, manage "Agent Spaces" (project-specific environments), and configure integrations.
* **Security Agent Web App**: The primary interface for developers to upload design documents, run penetration tests, and review findings.
* **Code Repository Integration**: Currently supports **GitHub**, enabling automated PR reviews and direct code remediation.

## Security & Privacy

* **Data Privacy**: Your queries and data are **never** used to train the underlying AI models.
* **Encryption**: All data is encrypted at rest via AWS KMS and in transit using TLS 1.2+.
* **Auditing**: All API activity is logged to **AWS CloudTrail** for full compliance and auditing visibility.

## Workflow and Implementation Steps

AWS Security Agent follows a comprehensive workflow that transitions from centralized administrative configuration in the AWS Management Console to decentralized security execution within a dedicated web application and your existing developer workflows.

1. **Administrative Setup** (AWS Console) - Before security assessments can begin, an administrator must establish the foundational environment:
   * **Create Agent Space**: Set up a dedicated workspace for each specific application or project.
   * **Define requirements**: Set organizational standards (e.g., encryption, logging) that apply globally to all reviews.
   * **Configure access**: Assign users via IAM Identity Center (for direct web app access) or provide IAM-only admin access (for users who already have AWS Console permissions).
   * **Register Integrations**: Connect your GitHub organization to enable code reviews and testing context.

2. **Design Security Review** (Web App) - Identify architectural risks before writing code:
   * **Upload documents**: Drag-and-drop design docs or architecture diagrams into the Web App.
   * **Analyze**: The agent validates designs against your custom organizational requirements.
   * **Review findings**: Review compliance status and follow specific guidance to fix insecure designs (the agent provides specific remediation guidance to resolve identified risks).

3. **Automated Code Security Review** (GitHub) - Once configured, code reviews happen automatically within the developer's native environment:
   * **Enable Repository monitoring**: Select specific repositories in the AWS Console for monitoring.
   * **Submit Pull Request**: Submit a GitHub Pull Request; the agent automatically scans for vulnerabilities and policy violations against both AWS best practices and your custom organizational requirements.
   * **Actionable feedback**: View remediation guidance directly as comments within the GitHub PR thread.

4. **On-Demand Penetration Testing** (Web App) - Execute autonomous, multi-step attack chains on live applications:
   * **Verify ownership**: Before testing, administrators must verify ownership of the target domain using DNS TXT or HTTP Route validation.
   * **Contextualize**: Attach source code or API documentation to help the agent understand application logic.
   * **Execute**: The agent autonomously plans, tests, and validates findings to reduce false positives.
   * **Remediation**: Review reproducible attack paths and request an automated GitHub PR with ready-to-implement code fixes.
