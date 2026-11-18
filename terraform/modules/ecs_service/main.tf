# ECS Fargate cluster, task definitions (web + one-off migrate) and the service.

locals {
  container_name = "web"
  image          = "${var.repository_url}:${var.image_tag}"

  environment = [for k, v in merge(var.environment, {
    PORT                    = tostring(var.container_port)
    GUNICORN_WORKER_TMP_DIR = "/tmp"
  }) : { name = k, value = v }]

  secrets = [
    { name = "DJANGO_SECRET_KEY", valueFrom = var.django_secret_arn },
    { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
    { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
  ]

  base_container = {
    image                  = local.image
    essential              = true
    user                   = "10001:10001"
    readonlyRootFilesystem = true
    environment            = local.environment
    secrets                = local.secrets
    mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
    linuxParameters = {
      initProcessEnabled = true
      capabilities       = { drop = ["ALL"] }
    }
  }

  web_container = merge(local.base_container, {
    name         = local.container_name
    portMappings = [{ containerPort = var.container_port, protocol = "tcp", name = "http" }]
    stopTimeout  = 30
    healthCheck = {
      command     = ["CMD", "python", "/srv/app/healthcheck.py"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 20
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "web"
        mode                  = "non-blocking"
        max-buffer-size       = "25m"
      }
    }
  })

  migrate_container = merge(local.base_container, {
    name    = "migrate"
    command = ["python", "manage.py", "migrate", "--noinput"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "migrate"
      }
    }
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights is on in "enhanced" mode, which this Checkov release only recognises as "enabled"
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enhanced"
  }

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.app.name
      }
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.web_container])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  volume {
    name = "tmp"
  }
}

resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.name}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.migrate_container])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  volume {
    name = "tmp"
  }
}

resource "aws_ecs_service" "web" {
  name                               = "web"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = var.min_capacity
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60
  enable_execute_command             = false
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  wait_for_steady_state              = false

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # scripts/deploy.sh rolls out new task definition revisions and Application Auto
  # Scaling owns desired_count, so Terraform must not fight either of them.
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  depends_on = [aws_lb_listener.https]
}
