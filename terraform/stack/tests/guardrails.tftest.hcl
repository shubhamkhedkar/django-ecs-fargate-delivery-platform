# Offline guardrail tests against mocked AWS/random providers: no credentials are
# needed and nothing is created. Run `terraform test` from terraform/stack.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:ap-south-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-south-1:111122223333:log-group:mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/mock"
    }
  }

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:ap-south-1:111122223333:repository/release-ledger"
      repository_url = "111122223333.dkr.ecr.ap-south-1.amazonaws.com/release-ledger"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:ap-south-1:111122223333:secret:release-ledger-prod/django-secret-key-AbCdEf"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address = "release-ledger-prod.abc123.ap-south-1.rds.amazonaws.com"
      arn     = "arn:aws:rds:ap-south-1:111122223333:db:release-ledger-prod"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-south-1:111122223333:secret:rds!db-mock-AbCdEf"
        kms_key_id    = "arn:aws:kms:ap-south-1:111122223333:key/00000000-0000-0000-0000-000000000000"
        secret_status = "active"
      }]
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-south-1:111122223333:loadbalancer/app/release-ledger-prod/0123456789abcdef"
      arn_suffix = "app/release-ledger-prod/0123456789abcdef"
      dns_name   = "release-ledger-prod-123.ap-south-1.elb.amazonaws.com"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-south-1:111122223333:targetgroup/web-abc/0123456789abcdef"
      arn_suffix = "targetgroup/web-abc/0123456789abcdef"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::release-ledger-prod-alb-logs-111122223333"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-south-1:111122223333:release-ledger-prod-alarms"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:ap-south-1:111122223333:regional/webacl/release-ledger-prod-alb/mock"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:ap-south-1:111122223333:cluster/release-ledger-prod"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:ap-south-1:111122223333:task-definition/release-ledger-prod-web:1"
    }
  }
}

mock_provider "random" {}

variables {
  app_domain      = "ledger.example.com"
  certificate_arn = "arn:aws:acm:ap-south-1:111122223333:certificate/00000000-0000-0000-0000-000000000000"
  image_tag       = "0123abc"
}

run "ecr_is_immutable_scanned_and_encrypted" {
  command = apply

  assert {
    condition     = module.ecr.image_tag_mutability == "IMMUTABLE"
    error_message = "ECR tags must be immutable."
  }

  assert {
    condition     = module.ecr.scan_on_push
    error_message = "ECR must scan on push."
  }

  assert {
    condition     = module.ecr.encryption_type == "KMS"
    error_message = "ECR must use KMS encryption."
  }

  assert {
    condition     = module.ecr.lifecycle_rule_count == 2
    error_message = "ECR needs untagged + tagged lifecycle rules."
  }
}

run "network_is_three_tier_and_private" {
  command = apply

  assert {
    condition     = length(module.network.app_subnet_ids) == 2 && length(module.network.db_subnet_ids) == 2
    error_message = "Expected app and db subnets in two AZs."
  }

  assert {
    condition     = module.network.nat_gateway_count == 2
    error_message = "Default layout uses one NAT gateway per AZ."
  }

  assert {
    condition     = !module.network.public_subnets_assign_public_ip
    error_message = "Public subnets must not auto-assign public IPs."
  }

  assert {
    condition     = module.network.flow_log_traffic_type == "ALL"
    error_message = "Flow logs must capture all traffic."
  }

  assert {
    condition     = contains(module.network.interface_endpoint_services, "ecr.dkr") && contains(module.network.interface_endpoint_services, "secretsmanager")
    error_message = "ECR and Secrets Manager endpoints are required."
  }

  assert {
    condition     = length(setintersection(module.network.subnet_cidrs.app, module.network.subnet_cidrs.db)) == 0
    error_message = "Subnet tiers must not overlap."
  }
}

run "single_nat_gateway_option" {
  command = apply

  variables {
    single_nat_gateway = true
    az_count           = 3
  }

  assert {
    condition     = module.network.nat_gateway_count == 1 && length(module.network.app_subnet_ids) == 3
    error_message = "single_nat_gateway should create exactly one NAT for three AZs."
  }
}

run "database_is_private_encrypted_and_tls_only" {
  command = apply

  assert {
    condition     = !module.database.publicly_accessible
    error_message = "RDS must not be public."
  }

  assert {
    condition     = module.database.storage_encrypted && module.database.multi_az
    error_message = "RDS must be encrypted and Multi-AZ by default."
  }

  assert {
    condition     = module.database.manages_master_password
    error_message = "RDS must manage the master password in Secrets Manager."
  }

  assert {
    condition     = module.database.force_ssl == "1"
    error_message = "rds.force_ssl must be on."
  }
}

run "task_definition_is_hardened" {
  command = apply

  assert {
    condition     = module.ecs_service.container_user == "10001:10001"
    error_message = "Container must run as the non-root app user."
  }

  assert {
    condition     = module.ecs_service.container_read_only_root
    error_message = "Root filesystem must be read-only."
  }

  assert {
    condition     = module.ecs_service.container_image == "111122223333.dkr.ecr.ap-south-1.amazonaws.com/release-ledger:0123abc"
    error_message = "Image must come from the stack's ECR repo, pinned to the git SHA tag."
  }

  assert {
    condition     = module.ecs_service.container_secret_names == tolist(["DB_PASSWORD", "DB_USER", "DJANGO_SECRET_KEY"])
    error_message = "Secrets must be injected from Secrets Manager, not plain env."
  }

  assert {
    condition     = length(setintersection(module.ecs_service.container_env_names, ["DJANGO_SECRET_KEY", "DB_PASSWORD"])) == 0
    error_message = "No secret may appear in plain environment variables."
  }
}

run "iam_is_least_privilege" {
  command = apply

  assert {
    condition     = length(module.ecs_service.execution_role_secret_arns) == 2
    error_message = "Execution role may read exactly the two injected secrets."
  }

  assert {
    condition     = alltrue([for a in module.ecs_service.execution_role_secret_arns : startswith(a, "arn:aws:secretsmanager:")])
    error_message = "Execution role secret scope must be concrete secret ARNs, not wildcards."
  }
}

run "service_is_private_and_self_healing" {
  command = apply

  assert {
    condition     = !module.ecs_service.assign_public_ip
    error_message = "Tasks must not get public IPs."
  }

  assert {
    condition     = module.ecs_service.circuit_breaker_rollback
    error_message = "Deployment circuit breaker must roll back failed deployments."
  }

  assert {
    condition     = !module.ecs_service.execute_command_enabled
    error_message = "ECS Exec stays off by default."
  }

  assert {
    condition     = module.ecs_service.autoscaling_range == [2, 6]
    error_message = "Default autoscaling range is 2-6 tasks."
  }

  assert {
    condition     = module.ecs_service.scaling_policy_types == tolist(["ALBRequestCountPerTarget", "ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization"])
    error_message = "Expected CPU, memory and request-count target tracking."
  }
}

run "edge_is_tls_only_with_waf" {
  command = apply

  assert {
    condition     = module.ecs_service.https_ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS listener must use the TLS 1.2/1.3 policy."
  }

  assert {
    condition     = module.ecs_service.http_listener_action == "redirect"
    error_message = "Port 80 must only redirect."
  }

  assert {
    condition     = module.ecs_service.alb_drops_invalid_headers
    error_message = "ALB must drop invalid header fields."
  }

  assert {
    condition     = module.ecs_service.target_group_health_path == "/healthz"
    error_message = "ALB must probe /healthz."
  }

  assert {
    condition     = contains(module.ecs_service.waf_rule_names, "AWSManagedRulesKnownBadInputsRuleSet") && contains(module.ecs_service.waf_rule_names, "rate-limit-per-ip")
    error_message = "WAF needs known-bad-inputs and rate limiting."
  }
}

run "alarms_are_wired" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 5
    error_message = "Expected five alarms."
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : contains(a.alarm_actions, aws_sns_topic.alarms.arn)])
    error_message = "Every alarm must notify the SNS topic."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email subscription unless alarm_email is set."
  }
}

run "rejects_mutable_image_tag" {
  command = plan

  variables {
    image_tag = "latest"
  }

  expect_failures = [var.image_tag]
}

run "rejects_non_acm_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:iam::111122223333:server-certificate/legacy"
  }

  expect_failures = [var.certificate_arn]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}
