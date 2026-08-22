# ============================================================
# S3 — パイプラインのartifactバケット（Source/Build成果物の受け渡し）
# ============================================================
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # destroy時にartifact残留で失敗しないように（Phase 5と同じ方針）

  tags = {
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket                  = aws_s3_bucket.pipeline_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# CodePipelineサービスロール — Source(GitHub接続の使用)・
# Build(CodeBuild起動)・Deploy(ECSサービス更新)それぞれに必要な
# 権限だけをリソース単位で付与
# ============================================================
resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project_name}-codepipeline"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketVersioning", "s3:GetBucketLocation"]
        Resource = ["${aws_s3_bucket.pipeline_artifacts.arn}", "${aws_s3_bucket.pipeline_artifacts.arn}/*"]
      },
      {
        Sid      = "UseGithubConnection"
        Effect   = "Allow"
        Action   = "codestar-connections:UseConnection"
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Sid      = "RunCodeBuild"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.app.arn
      },
      {
        # 実機検証の結果、AWS公式ドキュメントが示す6アクション
        # （DescribeServices/DescribeTaskDefinition/DescribeTasks/
        # ListTasks/RegisterTaskDefinition/UpdateService）だけでは
        # Deployステージが毎回 "PermissionError: The provided role does
        # not have sufficient permissions to access ECS" で即失敗した。
        # iam:simulate-principal-policyでこの6アクション全てが
        # "allowed"と評価される状態でも失敗が再現したため、IAM上の
        # 実効権限の問題ではなく、CodePipelineのECSデプロイアクションが
        # 実行前に行う権限チェック自体がecs:*ワイルドカードの存在を
        # 要求している（個別列挙では通らない）と判断。ecs:DescribeClusters
        # 追加、さらにTagResource/UntagResource/ListTagsForResource/
        # DescribeTaskSets/CreateTaskSet/DeleteTaskSet/
        # UpdateServicePrimaryTaskSet等を束ねて追加しても解決せず、
        # ecs:*のみが機能したことで確認済み（2026-08-22実機テスト）。
        # 本来の最小権限原則からは外れるが、この一点はCodePipeline側の
        # 仕様/挙動によるものとして受け入れる
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = "ecs:*"
        Resource = "*"
      },
      {
        # RegisterTaskDefinitionで新しいリビジョンに引き継がせるロールを
        # 「渡す」ための権限。当初はPhase 5の2ロールのARNで厳密に絞って
        # いたが、CodePipelineのECSデプロイアクションが起動前に行う
        # 権限チェック（PermissionError: "provided role does not have
        # sufficient permissions to access ECS"）がARN限定のPassRoleを
        # 正しく認識せず失敗した（実機で確認）。AWS公式ドキュメントの
        # ECSデプロイアクション用ポリシー例に合わせ、Resource="*"+
        # iam:PassedToServiceのCondition（ecs-tasks.amazonaws.comへの
        # PassRoleのみ許可）に変更——実質的な絞り込みはConditionが担う
        Sid      = "PassEcsTaskRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = ["ecs-tasks.amazonaws.com"]
          }
        }
      },
    ]
  })
}

# ============================================================
# CodePipeline本体 — Source → Build → Approve → Deploy
# 自動トリガーは意図的に設定しない（理由はdocs/Architecture.md参照。
# Phase 5の既存GitHub Actionsワークフローと二重デプロイになるのを避ける）
# ============================================================
resource "aws_codepipeline" "app" {
  name          = var.project_name
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  stage {
    name = "Approve"

    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        CustomData = "Review the new image pushed to ECR, then approve to deploy it to the Phase 5 ECS service."
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName = var.phase5_project_name
        ServiceName = var.phase5_project_name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  # トリガーを設定しない = 手動実行専用
  # （aws codepipeline start-pipeline-execution / コンソールの"Release change"）

  tags = {
    Project = var.project_name
  }
}
