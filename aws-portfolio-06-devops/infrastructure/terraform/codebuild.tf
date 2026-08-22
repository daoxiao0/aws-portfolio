data "aws_caller_identity" "current" {}

# ============================================================
# CodeBuild — Dockerイメージのbuild & ECR push
# privileged_mode = true が必須（CodeBuild内でdocker buildを実行するため）
# ============================================================

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project_name}-codebuild"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:*",
        ]
      },
      {
        # ECR認証トークンの取得はリソースレベル権限に対応しないため
        # （AWS仕様）、この1アクションのみResource: "*"が必須
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.phase5_project_name}"
      },
      {
        Sid      = "PipelineArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation"]
        Resource = ["${aws_s3_bucket.pipeline_artifacts.arn}", "${aws_s3_bucket.pipeline_artifacts.arn}/*"]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 14

  tags = {
    Project = var.project_name
  }
}

resource "aws_codebuild_project" "app" {
  name         = var.project_name
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true # dockerを動かすのに必須
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "aws-portfolio-06-devops/buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  tags = {
    Project = var.project_name
  }
}
