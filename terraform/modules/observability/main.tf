# CloudWatch Log Metric Filter - ERROR pattern
# Scans Lambda logs for "ERROR" string, emits custom metric for each match
# Use case: Track application-level errors beyond Lambda platform metrics
resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  name           = "${var.lambda_function_name}-error-count"
  log_group_name = "/aws/lambda/${var.lambda_function_name}"
  pattern        = "ERROR" # Case-sensitive literal match

  metric_transformation {
    name      = "ErrorCount"
    namespace = "DevOpsAgentDemo" # Custom namespace (not AWS/Lambda)
    value     = "1"               # Increment by 1 per match
    unit      = "Count"
  }
}

# CloudWatch Alarm - Lambda Errors
# Monitors AWS/Lambda Errors metric (platform-reported invocation failures)
# Alarm fires on ANY error within a 60s window
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.lambda_function_name}-errors"
  alarm_description   = "Lambda function errors detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1   # Trigger after 1 consecutive breaching period
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60  # 60s evaluation window
  statistic           = "Sum"
  threshold           = 1   # >= 1 error triggers alarm
  treat_missing_data  = "notBreaching" # No data = healthy (avoid false alarms during low traffic)

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [var.sns_topic_arn] # SNS notification when ALARM state entered
  ok_actions    = [var.sns_topic_arn] # SNS notification when OK state entered (recovery)

  tags = var.tags
}

# CloudWatch Alarm - Lambda Duration (p99)
# Monitors tail latency (99th percentile) to catch slow invocations
# metric_query required for percentile stats (p50, p90, p99)
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.lambda_function_name}-duration"
  alarm_description   = "Lambda function duration exceeded threshold (p99 > 5000ms)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1      # Trigger after 1 consecutive breaching period
  threshold           = 5000   # 5000ms = 5s (alarm if p99 > 5s)
  treat_missing_data  = "notBreaching"

  # metric_query block enables percentile statistics (not available in simple metric_name/statistic)
  metric_query {
    id          = "m1"
    return_data = true # This query's result is used for alarm evaluation

    metric {
      metric_name = "Duration"
      namespace   = "AWS/Lambda"
      period      = 60 # 60s evaluation window
      stat        = "p99" # 99th percentile (1% of invocations slower than this)

      dimensions = {
        FunctionName = var.lambda_function_name
      }
    }
  }

  alarm_actions = [var.sns_topic_arn] # SNS notification on ALARM
  ok_actions    = [var.sns_topic_arn] # SNS notification on recovery

  tags = var.tags
}
