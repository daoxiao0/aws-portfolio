output "sns_topic_arn" {
  description = "アラーム通知トピック。他スタックからのSubscribe追加等に使用"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  description = "CloudWatch Dashboardの直リンク"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_subscription_note" {
  description = "リマインド: applyしただけでは通知は届かない"
  value       = "AWSから${var.alert_email}宛に届く確認メールのリンクをクリックするまで、SNSサブスクリプションはPending状態のまま通知が届きません。"
}
