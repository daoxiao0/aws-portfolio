# ============================================================
# CloudWatch Logs — Lambdaロググループの保持期間設定
# デフォルトでは無期限保持（コスト増の原因）。14日に制限する。
# 注意: これら4つのロググループはPhase 3のLambda関数が既に呼び出し済みのため
# AWS側で自動作成されている。このリソースを新規createすると
# ResourceAlreadyExistsExceptionになるため、apply前に必ず
# `terraform import` で既存のロググループを取り込む
# （手順は infrastructure/terraform/README.md 参照）
# ============================================================
resource "aws_cloudwatch_log_group" "phase3_lambda" {
  for_each = toset(var.phase3_lambda_function_names)

  name              = "/aws/lambda/${each.value}"
  retention_in_days = 14

  tags = {
    Project = var.project_name
  }
}
