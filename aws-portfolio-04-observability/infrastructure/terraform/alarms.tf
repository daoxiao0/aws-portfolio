# ============================================================
# CloudWatch Alarms — Phase 3稼働リソースの異常検知
# 全アラームは aws_sns_topic.alerts へ通知する
# ============================================================

# ----------------------------------------------------------
# Lambda — 4関数それぞれのエラー検知（5分間で1件以上）
# ----------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.phase3_lambda_function_names)

  alarm_name        = "${var.project_name}-${each.value}-errors"
  alarm_description = "${each.value} が5分間で1回以上エラーを返した"
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions = {
    FunctionName = each.value
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Project = var.project_name
  }
}

# ----------------------------------------------------------
# API Gateway（HTTP API）— 5xx（サーバー側エラー）
# HTTP APIのメトリクス名はREST APIの"5XXError"と異なり"5xx"（小文字）
# ----------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name        = "${var.project_name}-api-gateway-5xx"
  alarm_description = "Phase 3 API Gatewayが5分間で1回以上5xxを返した"
  namespace         = "AWS/ApiGateway"
  metric_name       = "5xx"
  dimensions = {
    ApiId = var.phase3_api_gateway_id
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Project = var.project_name
  }
}

# ----------------------------------------------------------
# DynamoDB — スロットリング（オンデマンドテーブルでも発生しうる）
# ----------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name        = "${var.project_name}-dynamodb-throttles"
  alarm_description = "Phase 3のDynamoDBテーブルが5分間で1回以上スロットリングされた"
  namespace         = "AWS/DynamoDB"
  metric_name       = "ThrottledRequests"
  dimensions = {
    TableName = var.phase3_dynamodb_table_name
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Project = var.project_name
  }
}

# ----------------------------------------------------------
# CloudFront — 5xxErrorRate（Phase 1静的サイト・Phase 3フロントエンド）
# CloudFrontのメトリクスはus-east-1にしか存在しないため provider を切り替える
# ----------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cloudfront_phase1_5xx" {
  provider = aws.us_east_1

  alarm_name        = "${var.project_name}-cloudfront-phase1-5xx-rate"
  alarm_description = "Phase 1 CloudFrontの5xxエラー率が5%を超えた"
  namespace         = "AWS/CloudFront"
  metric_name       = "5xxErrorRate"
  dimensions = {
    DistributionId = var.phase1_cloudfront_distribution_id
    Region         = "Global"
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts_us_east_1.arn]
  ok_actions    = [aws_sns_topic.alerts_us_east_1.arn]

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_phase3_5xx" {
  provider = aws.us_east_1

  alarm_name        = "${var.project_name}-cloudfront-phase3-5xx-rate"
  alarm_description = "Phase 3フロントエンドCloudFrontの5xxエラー率が5%を超えた"
  namespace         = "AWS/CloudFront"
  metric_name       = "5xxErrorRate"
  dimensions = {
    DistributionId = var.phase3_cloudfront_distribution_id
    Region         = "Global"
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts_us_east_1.arn]
  ok_actions    = [aws_sns_topic.alerts_us_east_1.arn]

  tags = {
    Project = var.project_name
  }
}
