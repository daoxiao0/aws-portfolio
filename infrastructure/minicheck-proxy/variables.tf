variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "domain_name" {
  description = "このプロキシに割り当てるカスタムドメイン名"
  type        = string
  default     = "minicheck.daoxiao.org"
}

variable "origin_domain_name" {
  description = "プロキシ先のCloudflare Workersドメイン（末尾スラッシュなし）"
  type        = string
  default     = "minicheck.whycreator.workers.dev"
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for daoxiao.org（Phase 2/3と共通）"
  type        = string
  default     = "Z06510601ASWSVLJJY29P"
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "minicheck-cn-proxy"
}
