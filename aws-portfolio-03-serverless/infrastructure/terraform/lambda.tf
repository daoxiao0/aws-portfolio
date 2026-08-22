# ============================================================
# Lambda 実行ロール（関数ごとに分離・最小権限）
# 4つのLambda関数は以前は1つの共有ロールを使い、DynamoDBの全CRUD権限
# （PutItem/GetItem/Query/UpdateItem/DeleteItem）を4関数すべてに一律付与
# していた。各ハンドラーが実際に呼ぶAPIは1種類のみなので、関数ごとに
# 専用ロール＋そのAPI1つだけを許可するポリシーに分離する。
# 設計判断の詳細は docs/IAM-Least-Privilege.md 参照
# ============================================================

# 4ロール共通の信頼ポリシー（Lambdaサービスのみがこのロールを引き受けられる）
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ----------------------------------------------------------
# create_entry — dynamodb:PutItem のみ（backend/lambda/create_entry/handler.py 参照）
# ----------------------------------------------------------
resource "aws_iam_role" "create_entry" {
  name               = "${var.project_name}-create-entry-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "create_entry_logs" {
  role       = aws_iam_role.create_entry.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Phase 4 (Observability): X-Ray への書き込み権限。トレーシング自体は
# aws_lambda_function.create_entry の tracing_config で有効化する
resource "aws_iam_role_policy_attachment" "create_entry_xray" {
  role       = aws_iam_role.create_entry.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "create_entry_dynamodb" {
  name = "${var.project_name}-create-entry-dynamodb"
  role = aws_iam_role.create_entry.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.entries.arn
      }
    ]
  })
}

# ----------------------------------------------------------
# list_entries — dynamodb:Query のみ（backend/lambda/list_entries/handler.py 参照）
# ----------------------------------------------------------
resource "aws_iam_role" "list_entries" {
  name               = "${var.project_name}-list-entries-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "list_entries_logs" {
  role       = aws_iam_role.list_entries.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "list_entries_xray" {
  role       = aws_iam_role.list_entries.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "list_entries_dynamodb" {
  name = "${var.project_name}-list-entries-dynamodb"
  role = aws_iam_role.list_entries.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = aws_dynamodb_table.entries.arn
      }
    ]
  })
}

# ----------------------------------------------------------
# update_entry — dynamodb:UpdateItem のみ（backend/lambda/update_entry/handler.py 参照）
# ----------------------------------------------------------
resource "aws_iam_role" "update_entry" {
  name               = "${var.project_name}-update-entry-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "update_entry_logs" {
  role       = aws_iam_role.update_entry.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "update_entry_xray" {
  role       = aws_iam_role.update_entry.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "update_entry_dynamodb" {
  name = "${var.project_name}-update-entry-dynamodb"
  role = aws_iam_role.update_entry.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.entries.arn
      }
    ]
  })
}

# ----------------------------------------------------------
# delete_entry — dynamodb:DeleteItem のみ（backend/lambda/delete_entry/handler.py 参照）
# ----------------------------------------------------------
resource "aws_iam_role" "delete_entry" {
  name               = "${var.project_name}-delete-entry-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "delete_entry_logs" {
  role       = aws_iam_role.delete_entry.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "delete_entry_xray" {
  role       = aws_iam_role.delete_entry.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "delete_entry_dynamodb" {
  name = "${var.project_name}-delete-entry-dynamodb"
  role = aws_iam_role.delete_entry.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.entries.arn
      }
    ]
  })
}

# ============================================================
# Lambda関数コードのzip化
# archive プロバイダで各ハンドラーのディレクトリをzip化する
# ============================================================
data "archive_file" "create_entry" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambda/create_entry"
  output_path = "${path.module}/build/create_entry.zip"
}

data "archive_file" "list_entries" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambda/list_entries"
  output_path = "${path.module}/build/list_entries.zip"
}

data "archive_file" "update_entry" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambda/update_entry"
  output_path = "${path.module}/build/update_entry.zip"
}

data "archive_file" "delete_entry" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambda/delete_entry"
  output_path = "${path.module}/build/delete_entry.zip"
}

# ============================================================
# Lambda関数本体（4本）
# ランタイム: Python 3.12
# ============================================================
resource "aws_lambda_function" "create_entry" {
  function_name    = "${var.project_name}-create-entry"
  role             = aws_iam_role.create_entry.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.create_entry.output_path
  source_code_hash = data.archive_file.create_entry.output_base64sha256

  # Phase 4 (Observability): Lambdaサービスが自動でセグメントを生成する
  # （コード側のaws-xray-sdk計装は行わない。DynamoDBサブセグメントは出ないが
  # 呼び出しごとの実トレース＝関数名・所要時間・コールドスタートは記録される）
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.entries.name
    }
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_lambda_function" "list_entries" {
  function_name    = "${var.project_name}-list-entries"
  role             = aws_iam_role.list_entries.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.list_entries.output_path
  source_code_hash = data.archive_file.list_entries.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.entries.name
    }
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_lambda_function" "update_entry" {
  function_name    = "${var.project_name}-update-entry"
  role             = aws_iam_role.update_entry.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.update_entry.output_path
  source_code_hash = data.archive_file.update_entry.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.entries.name
    }
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_lambda_function" "delete_entry" {
  function_name    = "${var.project_name}-delete-entry"
  role             = aws_iam_role.delete_entry.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.delete_entry.output_path
  source_code_hash = data.archive_file.delete_entry.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.entries.name
    }
  }

  tags = {
    Project = var.project_name
  }
}
