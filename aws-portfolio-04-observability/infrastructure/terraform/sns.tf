# ============================================================
# SNS — アラーム通知トピック
# CloudWatch Alarmが発火した際にメールで通知する
# ============================================================
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # 注意: サブスクリプションはterraform applyだけでは有効化されない。
  # AWSがendpointに確認メールを送るので、そのメール内のリンクを
  # クリックして初めて"Confirmed"状態になる（それまではPending、通知は届かない）
}

# ============================================================
# us-east-1専用のセカンドトピック
# CloudWatch Alarmのalarm_actionsに指定するSNSトピックは、アラームと
# 同一リージョンでなければならない（"cross-region alarm action"は不可）。
# CloudFrontのメトリクス/アラームはus-east-1固定のため、東京リージョンの
# aws_sns_topic.alerts をそのまま参照するとPutMetricAlarmが
# "Invalid region ap-northeast-1 specified. Only us-east-1 is supported."
# で失敗する（実際に遭遇）。同じ宛先に届くよう、もう1つトピックを作る
# ============================================================
resource "aws_sns_topic" "alerts_us_east_1" {
  provider = aws.us_east_1
  name     = "${var.project_name}-alerts-us-east-1"

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic_subscription" "alerts_us_east_1_email" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts_us_east_1.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
