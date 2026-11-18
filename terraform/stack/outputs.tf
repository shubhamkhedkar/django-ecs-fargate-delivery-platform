output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "alb_dns_name" {
  description = "Point a CNAME/alias for app_domain at this name."
  value       = module.ecs_service.alb_dns_name
}

output "cluster_name" {
  value = module.ecs_service.cluster_name
}

output "service_name" {
  value = module.ecs_service.service_name
}

output "web_task_family" {
  value = module.ecs_service.web_task_family
}

output "migrate_task_family" {
  value = module.ecs_service.migrate_task_family
}

output "container_name" {
  value = module.ecs_service.container_name
}

output "app_subnet_ids" {
  value = module.network.app_subnet_ids
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "log_group_name" {
  value = module.ecs_service.log_group_name
}

output "db_endpoint" {
  value = module.database.address
}

output "alarm_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

# Shell-friendly block consumed by scripts/deploy.sh (terraform output -json deploy_config).
output "deploy_config" {
  value = {
    region          = var.region
    ecr_repository  = module.ecr.repository_url
    cluster         = module.ecs_service.cluster_name
    service         = module.ecs_service.service_name
    web_family      = module.ecs_service.web_task_family
    migrate_family  = module.ecs_service.migrate_task_family
    container_name  = module.ecs_service.container_name
    subnets         = module.network.app_subnet_ids
    security_groups = [aws_security_group.app.id]
  }
}
