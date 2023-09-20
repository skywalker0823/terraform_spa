
variable "aws_region" {
  default = "us-east-1"
  type    = string
}

variable "aws_account_id" {}

variable "domain" {}

variable "wwwdomain" {}

variable "bucket_name" {}

variable "fqdn" {
  type = list(string)
}

# 指定 aws 為 provider
provider "aws" {
  region = var.aws_region
}















# 建置S3
resource "aws_s3_bucket" "b" {
  bucket = var.bucket_name
  # 儘管內有物件仍強制刪除
  force_destroy = true
  # website {
  #   index_document = "index.html"
  #   error_document = "index.html"
  # }
}

# 設置S3權限
resource "aws_s3_bucket_policy" "b" {
  bucket = var.bucket_name

  policy = <<EOF
  {
        "Version": "2008-10-17",
        "Id": "PolicyForCloudFrontPrivateContent",
        "Statement": [
            {
                "Sid": "AllowCloudFrontServicePrincipal",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudfront.amazonaws.com"
                },
                "Action": "s3:GetObject",
                "Resource": "${aws_s3_bucket.b.arn}/*",
                "Condition": {
                    "StringEquals": {
                      "AWS:SourceArn": "arn:aws:cloudfront::${var.aws_account_id}:distribution/${aws_cloudfront_distribution.s3_distribution.id}"
                    }
                }
            }
        ]
  }
  EOF
}

# build 後上傳到S3
resource "null_resource" "build" {
  provisioner "local-exec" {
    command = "cd my-app && npm i && npm run build"
  }
  depends_on = [aws_s3_bucket.b]
}

# depend on build 完成後 deploy 到S3
resource "null_resource" "deploy" {
  provisioner "local-exec" {
    command = "aws s3 sync my-app/build/ s3://${var.bucket_name}"
  }
  depends_on = [null_resource.build]
}








# Route53 zone data
data "aws_route53_zone" "zone" {
  name         = "${var.domain}."
  private_zone = false
}



# 設置 certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
}



# 待釐清
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id = data.aws_route53_zone.zone.id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

# 待釐清
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn = aws_acm_certificate.cert.arn
  # fqdn 就是 fully qualified domain name
  # need to be *.example.com
  # validation_record_fqdns = [for record in aws_acm_certificate.cert.domain_validation_options : record.resource_record_name]
  validation_record_fqdns = [for record in aws_acm_certificate.cert.domain_validation_options : record.resource_record_name]
}












# 建置Cloudfront
locals {
  s3_origin_id = "S3-${var.bucket_name}"
}

resource "aws_cloudfront_origin_access_control" "s3_origin_access_identity" {
  signing_behavior = "always"
  signing_protocol = "sigv4"
  # depends_on                        = [aws_cloudfront_distribution.s3_distribution]
  name                              = local.s3_origin_id
  origin_access_control_origin_type = "s3"


}

resource "aws_cloudfront_distribution" "s3_distribution" {

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    # 應該是少這個
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_origin_access_identity.id

    # custom_origin_config {
    #   http_port              = 80
    #   https_port             = 443
    #   origin_protocol_policy = "http-only"
    #   origin_ssl_protocols   = ["TLSv1.1", "TLSv1.2"]
    # }
  }

  # logging_config {
  #   include_cookies = false
  #   bucket          = "${var.bucket_name}.s3.amazonaws.com"
  #   prefix          = "cloudfront_logs"
  # }

  aliases = ["${var.domain}"]


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
  }


  restrictions {
    geo_restriction {
      # restriction_type = "whitelist"
      # # locations        = ["US", "CA", "GB", "DE", "TW"]
      # accept all locations
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
    # cloudfront_default_certificate = true
    minimum_protocol_version = "TLSv1.1_2016"
  }


  # depends_on = [aws_acm_certificate.domain, aws_acm_certificate.wwwdomain]
  depends_on = [aws_acm_certificate_validation.cert, aws_route53_record.cert_validation]
}







# 建置Route53的cloudfront紀錄
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.zone.id
  name    = var.domain
  type    = "A"

  alias {
    name                   = replace(aws_cloudfront_distribution.s3_distribution.domain_name, "/[.]$/", "")
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_cloudfront_distribution.s3_distribution]
}








# 輸出結果
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "cloudfront_zone_id" {
  value = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
}

output "domain" {
  value = aws_route53_record.www.name
}


# 大致順序 
# 1. 建立s3 bucket
# 2. 建立s3 bucket policy
# 3. 上傳檔案到s3 bucket  
# 4. 建立ACM certificate
# 5. 待釐清x2
# 6. 建立cloudfront
# 7. 建立route53的cloudfront紀錄