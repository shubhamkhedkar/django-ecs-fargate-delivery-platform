# Django SECRET_KEY lives in Secrets Manager and is injected into the container by ECS.
# Note: the generated value is also stored in Terraform state, so keep state in an
# encrypted, access-controlled S3 backend.

resource "random_password" "django_secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "django" {
  #checkov:skip=CKV2_AWS_57:Rotating SECRET_KEY invalidates sessions; rotate deliberately (README: Rotating the Django secret key)
  name                    = "${local.name}/django-secret-key"
  description             = "Django SECRET_KEY for ${local.name}"
  kms_key_id              = aws_kms_key.platform.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "django" {
  secret_id     = aws_secretsmanager_secret.django.id
  secret_string = random_password.django_secret_key.result
}
