# Alarms for the signals that matter on day one, routed to an encrypted SNS topic.

resource "aws_sns_topic" "alarms" {
  name              = "${local.name}-alarms"
  kms_master_key_id = aws_kms_key.platform.arn
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = [aws_sns_topic.alarms.arn]

  alarms = {
    alb-5xx = {
      namespace   = "AWS/ApplicationELB"
      metric      = "HTTPCode_Target_5XX_Count"
      statistic   = "Sum"
      threshold   = 10
      comparison  = "GreaterThanThreshold"
      description = "Django returned more than 10 5xx responses in 5 minutes"
      dimensions  = { LoadBalancer = module.ecs_service.alb_arn_suffix }
    }
    unhealthy-targets = {
      namespace   = "AWS/ApplicationELB"
      metric      = "UnHealthyHostCount"
      statistic   = "Maximum"
      threshold   = 0
      comparison  = "GreaterThanThreshold"
      description = "At least one task is failing ALB health checks"
      dimensions = {
        LoadBalancer = module.ecs_service.alb_arn_suffix
        TargetGroup  = module.ecs_service.target_group_arn_suffix
      }
    }
    p95-latency = {
      namespace   = "AWS/ApplicationELB"
      metric      = "TargetResponseTime"
      statistic   = null
      extended    = "p95"
      threshold   = 1
      comparison  = "GreaterThanThreshold"
      description = "p95 target response time above 1s"
      dimensions  = { LoadBalancer = module.ecs_service.alb_arn_suffix }
    }
    rds-cpu = {
      namespace   = "AWS/RDS"
      metric      = "CPUUtilization"
      statistic   = "Average"
      threshold   = 80
      comparison  = "GreaterThanThreshold"
      description = "RDS CPU above 80%"
      dimensions  = { DBInstanceIdentifier = module.database.identifier }
    }
    rds-free-storage = {
      namespace   = "AWS/RDS"
      metric      = "FreeStorageSpace"
      statistic   = "Minimum"
      threshold   = 5368709120
      comparison  = "LessThanThreshold"
      description = "RDS free storage below 5 GiB"
      dimensions  = { DBInstanceIdentifier = module.database.identifier }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  extended_statistic  = lookup(each.value, "extended", null)
  dimensions          = each.value.dimensions
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
