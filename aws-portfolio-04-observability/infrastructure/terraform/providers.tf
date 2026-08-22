terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# CloudFrontのメトリクスはus-east-1にしか発行されないため、
# Phase 1・Phase 3フロントエンドの5xxエラー率アラームはこちらで作成する
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
