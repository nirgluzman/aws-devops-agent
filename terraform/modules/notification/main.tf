# ============================================================================
# Module: notification
# Purpose: Centralized alerting infrastructure for CloudWatch alarm notifications
# ============================================================================
#
# Architecture Flow:
#   Lambda (app_stack) → CloudWatch Alarms (observability) → SNS Topic (here) → Email
#
# Module Dependencies:
#   - Consumed by: observability module (receives sns_topic_arn output)
#   - Consumes: none (independent module)
#
# Notification Path:
#   1. Lambda function experiences errors or latency (app_stack module)
#   2. CloudWatch alarms detect threshold breaches (observability module)
#   3. Alarms trigger alarm_actions → this SNS topic
#   4. SNS topic fans out to subscriptions (email, optionally SMS/Lambda/etc.)
#   5. Email notifications delivered to ops team inbox
#
# Security:
#   - Topic encrypted at rest with AWS-managed KMS key (alias/aws/sns)
#   - Email subscription requires manual confirmation (click link in AWS email)
#
# Note: AWS DevOps Agent RCA is separate—viewed in Agent Space web app, not via SNS.
#       SNS emails contain alarm state changes only (ALARM/OK), not RCA findings.
#       For detailed root cause analysis, ops team must access Agent Space UI after
#       receiving the alarm notification.
# ============================================================================

# SNS Topic: Central hub for all DevOps Agent alert notifications
resource "aws_sns_topic" "alerts" {
  name              = "devops-agent-alerts"
  display_name      = "DevOps Agent Demo Alerts"
  kms_master_key_id = "alias/aws/sns" # Encrypt messages at rest (best practice)

  tags = var.tags
}

# Email Subscription: Delivers alarm notifications to ops team inbox
# IMPORTANT: Subscription starts in "PendingConfirmation" status until user clicks
# the confirmation link in the AWS email. No notifications are delivered until confirmed.
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # Email address from root module variable
}
