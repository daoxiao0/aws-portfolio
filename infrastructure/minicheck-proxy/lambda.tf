# CloudFrontとworkers.devの間に挟む転送Lambda。
# 経緯（なぜCloudFrontから直接workers.devを叩けないか）は
# docs-ja/0005-CloudFrontの源站フェッチャーがCloudflareに拒否される.md 参照。

data "archive_file" "proxy_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda-proxy/index.mjs"
  output_path = "${path.module}/lambda-proxy.zip"
}

resource "aws_iam_role" "proxy_lambda" {
  name = "minicheck-cn-proxy-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# 外部（workers.dev）へのfetch()にAWS API権限は不要。CloudWatch Logsへの
# 書き込みのみで足りる
resource "aws_iam_role_policy_attachment" "proxy_lambda_basic" {
  role       = aws_iam_role.proxy_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudFrontがLambdaを呼んでいることの検証に使う共有シークレット。
# 当初はOAC（SigV4署名）でアクセス制限していたが、POST等body付きリクエストで
# 署名不一致（SignatureDoesNotMatch）が発生したため、Function URLをNONE
# （公開）認証にし、この値をCloudFrontのカスタムオリジンヘッダー（cloudfront.tf）
# として送り、Lambda側（index.mjs）で検証する方式に変更した（詳細: docs-ja/0006）
resource "random_password" "proxy_secret" {
  length  = 32
  special = false
}

resource "aws_lambda_function" "proxy" {
  function_name = "minicheck-cn-proxy"
  role          = aws_iam_role.proxy_lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 20
  memory_size   = 128

  filename         = data.archive_file.proxy_lambda.output_path
  source_code_hash = data.archive_file.proxy_lambda.output_base64sha256

  environment {
    variables = {
      PROXY_SECRET = random_password.proxy_secret.result
    }
  }
}

# NONE（公開）にする。アクセス制限はOACのSigV4署名でなく、上記の
# 共有シークレットヘッダー（cloudfront.tf のカスタムオリジンヘッダー）で行う
resource "aws_lambda_function_url" "proxy" {
  function_name      = aws_lambda_function.proxy.function_name
  authorization_type = "NONE"
}

# NONE認証のFunction URLでも、誰でも呼べることを許可する明示的なリソース
# ポリシーが必要（付けないとFunction URL自体は作れても呼び出し時に拒否される）
resource "aws_lambda_permission" "allow_public_invoke_url" {
  statement_id           = "AllowPublicInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.proxy.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# 2024年以降に作成されたAWSアカウントには「Lambda Function URLの公開アクセス
# ブロック」が既定で有効になっており、AuthType=NONE + 上記の
# lambda:InvokeFunctionUrl 権限だけでは依然403になることが判明した
# （新規に作った完全に独立したテスト用Lambdaでも同じ403が再現し、account
# レベルの制約だと切り分けた）。lambda:InvokeFunction もPrincipal "*" で
# 明示的に許可することでこのブロックを回避できる（詳細: docs-ja/0006）
resource "aws_lambda_permission" "allow_public_invoke_function" {
  statement_id  = "AllowPublicInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "*"
}
