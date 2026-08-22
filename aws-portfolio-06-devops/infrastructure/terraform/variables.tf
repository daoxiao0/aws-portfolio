variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "project_name" {
  type    = string
  default = "aws-portfolio-06-devops"
}

variable "github_owner" {
  type    = string
  default = "daoxiao0"
}

variable "github_repo" {
  type    = string
  default = "aws-portfolio"
}

variable "github_branch" {
  type    = string
  default = "main"
}

# ---- Phase 5の既存リソース参照（別Terraform stateのため名前を直接参照。
#      github-oidc/main.tf・Phase 4と同じ方式） ----
variable "phase5_project_name" {
  description = "Phase 5のリソース名プレフィックス。ECRリポジトリ名・ECSクラスタ/サービス名として使用"
  type        = string
  default     = "aws-portfolio-05-containers"
}
