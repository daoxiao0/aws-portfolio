# CloudFront ディストリビューション
# minicheck.daoxiao.org 宛のリクエストを、転送用Lambda（lambda.tf）経由で
# Cloudflare Workersへ中継する。
#
# 当初はworkers.devを直接カスタムオリジンにしていたが、CloudFrontの源站
# フェッチャーからの接続だけがCloudflareに一貫して502で拒否された
# （openssl/curl/Lambdaからのfetch()はいずれも成功）。切り分けの結果、
# Cloudflareが意図的にCloudFrontの出口を拒否している可能性が高いと判断し、
# 実際の発信をLambda（動作確認済み）に移し、CloudFrontはクライアント向けの
# 窓口（カスタムドメイン・TLS終端・エッジ）に徹する構成に変更した
# （詳細: docs-ja/0005-CloudFrontの源站フェッチャーがCloudflareに拒否される.md）。
#
# Function URLへのアクセス制限は、当初CloudFront OAC（SigV4署名）で行って
# いたが、POST等body付きリクエストで署名不一致（SignatureDoesNotMatch）が
# 発生したため撤回した。代わりにカスタムオリジンヘッダーで共有シークレットを
# 送り、Lambda側で検証する方式にしている（詳細: docs-ja/0006）。
resource "aws_cloudfront_distribution" "proxy" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2"
  comment         = "MiniCheck CN Proxy -> Lambda -> ${var.origin_domain_name}"

  aliases = [var.domain_name]

  origin {
    # Function URLのドメイン部分だけを取り出す（https:// と末尾の / を除去）
    domain_name = trimsuffix(trimprefix(aws_lambda_function_url.proxy.function_url, "https://"), "/")
    origin_id   = "MiniCheckLambdaProxyOrigin"

    custom_header {
      name  = "X-MiniCheck-Proxy-Secret"
      value = random_password.proxy_secret.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "MiniCheckLambdaProxyOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.proxy.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
