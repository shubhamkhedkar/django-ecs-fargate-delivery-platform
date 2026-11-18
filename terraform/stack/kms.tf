# One customer-managed key for this stack: CloudWatch Logs, ECR, RDS storage and
# Performance Insights, Secrets Manager and SNS. Rotation is on.

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_356:In a key policy, Resource "*" means this key only
  #checkov:skip=CKV_AWS_111:Key policy; the account-root statement is the AWS-recommended default
  #checkov:skip=CKV_AWS_109:Key policy; the account-root statement keeps the key manageable via IAM
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:*"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsToSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "${local.name} platform key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.platform.key_id
}
