locals {
  rendered_web = jsondecode(aws_ecs_task_definition.web.container_definitions)[0]
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.web.name
}

output "web_task_family" {
  value = aws_ecs_task_definition.web.family
}

output "migrate_task_family" {
  value = aws_ecs_task_definition.migrate.family
}

output "container_name" {
  value = local.container_name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.web.arn_suffix
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

# --- facts asserted by the mocked terraform tests --------------------------------

output "container_user" {
  value = local.rendered_web.user
}

output "container_read_only_root" {
  value = local.rendered_web.readonlyRootFilesystem
}

output "container_image" {
  value = local.rendered_web.image
}

output "container_secret_names" {
  value = sort([for s in local.rendered_web.secrets : s.name])
}

output "container_env_names" {
  value = sort([for e in local.rendered_web.environment : e.name])
}

output "execution_role_secret_arns" {
  value = local.execution_secret_arns
}

output "assign_public_ip" {
  value = one(aws_ecs_service.web.network_configuration).assign_public_ip
}

output "circuit_breaker_rollback" {
  value = one(aws_ecs_service.web.deployment_circuit_breaker).rollback
}

output "execute_command_enabled" {
  value = aws_ecs_service.web.enable_execute_command
}

output "https_ssl_policy" {
  value = aws_lb_listener.https.ssl_policy
}

output "http_listener_action" {
  value = one(aws_lb_listener.http_redirect.default_action).type
}

output "alb_drops_invalid_headers" {
  value = aws_lb.this.drop_invalid_header_fields
}

output "target_group_health_path" {
  value = one(aws_lb_target_group.web.health_check).path
}

output "autoscaling_range" {
  value = [aws_appautoscaling_target.web.min_capacity, aws_appautoscaling_target.web.max_capacity]
}

output "scaling_policy_types" {
  value = sort([
    for p in [aws_appautoscaling_policy.cpu, aws_appautoscaling_policy.memory, aws_appautoscaling_policy.requests] :
    one(one(p.target_tracking_scaling_policy_configuration).predefined_metric_specification).predefined_metric_type
  ])
}

output "waf_rule_names" {
  value = sort(concat(keys(local.managed_rule_groups), ["AWSManagedRulesKnownBadInputsRuleSet", "rate-limit-per-ip"]))
}
