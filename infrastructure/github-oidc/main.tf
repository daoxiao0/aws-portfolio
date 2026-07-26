# CI identity for this repository's deployment workflows.
#
# Replaces a long-lived IAM user access key stored in GitHub Secrets. GitHub
# hands the workflow a short-lived OIDC token, AWS exchanges it for temporary
# credentials, and nothing durable is stored on either side.
#
# Deliberately its own stack: this identity spans every phase, so it does not
# belong to any one of them.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "aws-portfolio"
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "github_owner_id" {
  description = "Numeric account ID. gh api repos/OWNER/REPO --jq .owner.id"
  type        = number
}

variable "github_repository_id" {
  description = "Numeric repository ID. gh api repos/OWNER/REPO --jq .id"
  type        = number
}

# Created by the serverless-social-publisher stack. Only one OIDC provider for
# a given issuer may exist per account, so it is read here rather than created.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "deploy" {
  name        = "github-actions-aws-portfolio"
  description = "Deployment role assumed by this repository's GitHub Actions workflows"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Matched on immutable numeric IDs. Names are wildcards on purpose:
        # an account name that gets released can be registered by somebody
        # else, and a name-based policy would then trust their tokens.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:*@${var.github_owner_id}/*@${var.github_repository_id}:*"
        }
      }
    }]
  })
}

# Same permissions the IAM user held, resource by resource. Nothing is widened
# during the migration: a change of credential type should not be a change of
# authority.
resource "aws_iam_role_policy" "deploy" {
  name = "portfolio-deploy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Phase01StaticSite"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::portfolio-01-gratitude-2026-v2",
          "arn:aws:s3:::portfolio-01-gratitude-2026-v2/*",
        ]
      },
      {
        Sid      = "Phase01Invalidation"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "arn:aws:cloudfront::536697227701:distribution/E2A0IOWER5T8MD"
      },
      {
        Sid    = "Phase03Frontend"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::portfolio-03-serverless-frontend-536697227701",
          "arn:aws:s3:::portfolio-03-serverless-frontend-536697227701/*",
        ]
      },
      {
        Sid      = "Phase03Invalidation"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "arn:aws:cloudfront::536697227701:distribution/E3DWEBAN856KUZ"
      },
      {
        Sid    = "Phase03LambdaCode"
        Effect = "Allow"
        Action = "lambda:UpdateFunctionCode"
        Resource = [
          "arn:aws:lambda:ap-northeast-1:536697227701:function:aws-portfolio-03-serverless-create-entry",
          "arn:aws:lambda:ap-northeast-1:536697227701:function:aws-portfolio-03-serverless-list-entries",
          "arn:aws:lambda:ap-northeast-1:536697227701:function:aws-portfolio-03-serverless-update-entry",
          "arn:aws:lambda:ap-northeast-1:536697227701:function:aws-portfolio-03-serverless-delete-entry",
        ]
      },
    ]
  })
}

output "role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN secret on the repository."
  value       = aws_iam_role.deploy.arn
}
