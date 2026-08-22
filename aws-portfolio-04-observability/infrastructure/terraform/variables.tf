variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト識別子。リソース名のプレフィックスとして使用"
  type        = string
  default     = "aws-portfolio-04-observability"
}

variable "alert_email" {
  description = "アラーム通知の送付先メールアドレス（sns:Subscribeはメール内の確認リンクをクリックするまでPendingのまま）"
  type        = string
  default     = "daoxiao01230@gmail.com"
}

# ---- Phase 3の既存リソース参照（別Terraform stateのため名前/ARNを直接参照する。
#      infrastructure/github-oidc/main.tf と同じ方式） ----

variable "phase3_lambda_function_names" {
  description = "Phase 3の4つのLambda関数名"
  type        = list(string)
  default = [
    "aws-portfolio-03-serverless-create-entry",
    "aws-portfolio-03-serverless-list-entries",
    "aws-portfolio-03-serverless-update-entry",
    "aws-portfolio-03-serverless-delete-entry",
  ]
}

variable "phase3_api_gateway_id" {
  description = "Phase 3のHTTP API ID（api_endpointの https://<id>.execute-api... 部分）"
  type        = string
  default     = "06q0wokhfg"
}

variable "phase3_dynamodb_table_name" {
  description = "Phase 3のDynamoDBテーブル名"
  type        = string
  default     = "aws-portfolio-03-serverless-entries"
}

variable "phase1_cloudfront_distribution_id" {
  description = "Phase 1（静的サイト）のCloudFrontディストリビューションID"
  type        = string
  default     = "E2A0IOWER5T8MD"
}

variable "phase3_cloudfront_distribution_id" {
  description = "Phase 3フロントエンドのCloudFrontディストリビューションID"
  type        = string
  default     = "E3DWEBAN856KUZ"
}
