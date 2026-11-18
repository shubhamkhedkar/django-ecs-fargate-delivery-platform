# Two roles, deliberately separate (CKV_AWS_249):
#  - execution role: used by the ECS agent to pull the image, write logs and read the
#    exact secrets referenced in the task definition. Nothing else.
#  - task role: the identity of the Django process. It needs no AWS API access today,
#    so it has no permissions at all.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${var.partition}:ecs:${var.region}:${var.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

locals {
  execution_secret_arns = [var.django_secret_arn, var.db_secret_arn]
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid = "PullAppImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.repository_arn]
  }

  statement {
    sid       = "WriteAppLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }

  statement {
    sid       = "ReadInjectedSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.execution_secret_arns
  }

  statement {
    sid       = "DecryptSecretsAndImage"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${var.region}.amazonaws.com",
        "ecr.${var.region}.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "pull-image-logs-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}
