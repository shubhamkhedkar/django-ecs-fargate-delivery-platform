# Internet-facing ALB in public subnets: TLS 1.2/1.3 on 443, HTTP 80 only redirects.

resource "aws_lb" "this" {
  name                       = substr(var.name, 0, 32)
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [var.alb_security_group_id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.alb_deletion_protection
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "web" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB; ALB-to-task traffic stays inside private subnets
  name_prefix          = "web-"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# --- Access-log bucket ----------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_144:Access logs are regional operational data; cross-region replication is not needed
  #checkov:skip=CKV_AWS_145:ALB access-log delivery only supports SSE-S3 on the target bucket
  #checkov:skip=CKV2_AWS_62:No consumer needs event notifications for log objects
  #checkov:skip=CKV_AWS_18:This is the log bucket itself; logging it to itself would loop
  bucket        = "${var.name}-alb-logs-${var.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.alb_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AllowAlbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${var.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
