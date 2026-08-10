resource "aws_acm_certificate" "proxy" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Route 53 CNAME records for DNS validation（ACMが要求するレコードをそのまま作成する）
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.proxy.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

# 検証完了を待ってからCloudFrontに証明書を使わせる
resource "aws_acm_certificate_validation" "proxy" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.proxy.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
