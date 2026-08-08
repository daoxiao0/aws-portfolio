variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト識別子。リソース名のプレフィックスとして使用"
  type        = string
  default     = "aws-portfolio-03-serverless"
}

variable "domain_name" {
  description = "Phase 3フロントエンドのカスタムドメイン"
  type        = string
  default     = "journal.daoxiao.org"
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for daoxiao.org（Phase 2と共通）"
  type        = string
  default     = "Z06510601ASWSVLJJY29P"
}
