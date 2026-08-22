variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト識別子。リソース名のプレフィックスとして使用"
  type        = string
  default     = "aws-portfolio-05-containers"
}

# ---- ネットワーク：既存のデフォルトVPCを流用（新規VPC/IGW/ルートテーブルを
#      作らない・後で壊すものを増やさない）。NAT Gatewayも作らない
#      （最大の不要固定費・月$32〜35。デモ用途では不要と判断——理由は
#      docs/Architecture.md参照） ----
variable "vpc_id" {
  description = "既存のデフォルトVPC（aws ec2 describe-vpcsで確認）"
  type        = string
  default     = "vpc-0046de735c86c4c3a"
}

variable "public_subnet_ids" {
  description = "デフォルトVPCの公開サブネット（3AZ）。ALB・ECSタスク・RDSすべてここに置く"
  type        = list(string)
  default = [
    "subnet-04563297017f11ca9", # ap-northeast-1d
    "subnet-025ec28a4b7bec4f6", # ap-northeast-1a
    "subnet-0ca0b62a29d8b039b", # ap-northeast-1c
  ]
}

variable "db_name" {
  type    = string
  default = "portfolio05"
}

variable "db_username" {
  type    = string
  default = "portfolio05admin"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "image_tag" {
  description = "ECRにpush済みのイメージタグ。deploy-05-containers-image.ymlがpush後に更新する"
  type        = string
  default     = "latest"
}
