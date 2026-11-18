data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first az_count zones are used, so new zones never change the layout
  state = "available"
}

locals {
  name       = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "network" {
  source = "../modules/network"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = local.azs
  region             = var.region
  account_id         = local.account_id
  single_nat_gateway = var.single_nat_gateway
  kms_key_arn        = aws_kms_key.platform.arn
  log_retention_days = var.log_retention_days
}

module "ecr" {
  source = "../modules/ecr"

  name        = var.project
  kms_key_arn = aws_kms_key.platform.arn
}

module "database" {
  source = "../modules/database"

  name                = local.name
  partition           = local.partition
  subnet_ids          = module.network.db_subnet_ids
  security_group_id   = aws_security_group.db.id
  kms_key_arn         = aws_kms_key.platform.arn
  engine_version      = var.db_engine_version
  instance_class      = var.db_instance_class
  multi_az            = var.db_multi_az
  deletion_protection = var.deletion_protection
}

module "ecs_service" {
  source = "../modules/ecs_service"

  name                  = local.name
  region                = var.region
  account_id            = local.account_id
  partition             = local.partition
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_subnet_ids        = module.network.app_subnet_ids
  alb_security_group_id = aws_security_group.alb.id
  app_security_group_id = aws_security_group.app.id
  certificate_arn       = var.certificate_arn

  repository_url   = module.ecr.repository_url
  repository_arn   = module.ecr.repository_arn
  image_tag        = var.image_tag
  cpu              = var.task_cpu
  memory           = var.task_memory
  cpu_architecture = var.cpu_architecture
  min_capacity     = var.min_capacity
  max_capacity     = var.max_capacity

  django_secret_arn = aws_secretsmanager_secret.django.arn
  db_secret_arn     = module.database.master_user_secret_arn
  kms_key_arn       = aws_kms_key.platform.arn

  log_retention_days      = var.log_retention_days
  alb_deletion_protection = var.deletion_protection

  environment = {
    DJANGO_ALLOWED_HOSTS        = var.app_domain
    DJANGO_CSRF_TRUSTED_ORIGINS = "https://${var.app_domain}"
    DEPLOY_ENVIRONMENT          = var.environment
    DB_HOST                     = module.database.address
    DB_PORT                     = tostring(module.database.port)
    DB_NAME                     = module.database.db_name
    DB_SSLMODE                  = "require"
    WEB_CONCURRENCY             = "2"
  }
}
