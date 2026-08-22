# ============================================================
# CloudWatch Dashboard — Phase 3の全レイヤーを1画面に集約
# ダッシュボード自体はグローバルリソース。各widgetのregionプロパティで
# ap-northeast-1（Lambda/API Gateway/DynamoDB）とus-east-1（CloudFront）を
# 混在させている
# ============================================================
locals {
  lambda_metrics_invocations = [
    for fn in var.phase3_lambda_function_names : ["AWS/Lambda", "Invocations", "FunctionName", fn]
  ]
  lambda_metrics_errors = [
    for fn in var.phase3_lambda_function_names : ["AWS/Lambda", "Errors", "FunctionName", fn]
  ]
  lambda_metrics_duration = [
    for fn in var.phase3_lambda_function_names : ["AWS/Lambda", "Duration", "FunctionName", fn, { stat = "Average" }]
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Phase 3 — Serverless Gratitude Journal Observability"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda Invocations"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = local.lambda_metrics_invocations
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda Errors"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = local.lambda_metrics_errors
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda Duration (avg, ms)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = local.lambda_metrics_duration
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway — Count / 4xx / 5xx"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.phase3_api_gateway_id],
            ["AWS/ApiGateway", "4xx", "ApiId", var.phase3_api_gateway_id],
            ["AWS/ApiGateway", "5xx", "ApiId", var.phase3_api_gateway_id],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway Latency (avg, ms)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.phase3_api_gateway_id, { stat = "Average" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB — Consumed Capacity"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.phase3_dynamodb_table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.phase3_dynamodb_table_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB — Throttled Requests"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/DynamoDB", "ThrottledRequests", "TableName", var.phase3_dynamodb_table_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 12
        height = 6
        properties = {
          title  = "CloudFront — Requests (Phase 1 / Phase 3)"
          region = "us-east-1"
          view   = "timeSeries"
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.phase1_cloudfront_distribution_id, "Region", "Global", { label = "Phase 1" }],
            ["AWS/CloudFront", "Requests", "DistributionId", var.phase3_cloudfront_distribution_id, "Region", "Global", { label = "Phase 3" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 19
        width  = 12
        height = 6
        properties = {
          title  = "CloudFront — 5xx Error Rate (%)"
          region = "us-east-1"
          view   = "timeSeries"
          metrics = [
            ["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.phase1_cloudfront_distribution_id, "Region", "Global", { label = "Phase 1", stat = "Average" }],
            ["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.phase3_cloudfront_distribution_id, "Region", "Global", { label = "Phase 3", stat = "Average" }],
          ]
        }
      },
    ]
  })
}
