output "proxy_url" {
  description = "プロキシ経由でMiniCheckにアクセスするURL"
  value       = "https://${var.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID（キャッシュ無効化・デバッグ時に使用）"
  value       = aws_cloudfront_distribution.proxy.id
}

output "cloudfront_domain_name" {
  description = "CloudFrontが割り当てたデフォルトドメイン（*.cloudfront.net）"
  value       = aws_cloudfront_distribution.proxy.domain_name
}

output "certificate_arn" {
  description = "発行されたACM証明書のARN（us-east-1）"
  value       = aws_acm_certificate.proxy.arn
}
