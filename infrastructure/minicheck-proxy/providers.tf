# minicheck.daoxiao.org から Cloudflare Workers（minicheck.whycreator.workers.dev）への
# CloudFrontリバースプロキシ。中国大陸からCloudflareへ直接アクセスすると不安定に
# なる問題を回避するため、自分のAWSアカウントを経由させる。
#
# フェーズ進行（01→06）には属さない独立スタック。github-oidc と同様、
# どのフェーズにも属さないためここに置く。

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

# ACM証明書はCloudFrontで使うため us-east-1 固定が必須（Phase 02/03と同じ制約）
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
