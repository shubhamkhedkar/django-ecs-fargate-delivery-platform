variable "name" {
  description = "Name prefix (also the cluster name)."
  type        = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "partition" {
  type    = string
  default = "aws"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subnets for the ALB."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Private subnets for Fargate tasks."
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener."
  type        = string
}

variable "ssl_policy" {
  type    = string
  default = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "repository_url" {
  type = string
}

variable "repository_arn" {
  type = string
}

variable "image_tag" {
  description = "Immutable image tag (git SHA) for the initial task definition."
  type        = string
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64 (Graviton, cheaper; build the image for linux/arm64)."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "environment" {
  description = "Plain (non-secret) environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "django_secret_arn" {
  type = string
}

variable "db_secret_arn" {
  description = "RDS-managed master secret (JSON with username/password)."
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "alb_log_retention_days" {
  type    = number
  default = 90
}

variable "alb_deletion_protection" {
  type    = bool
  default = true
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per client IP before WAF blocks."
  type        = number
  default     = 2000
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6
}

variable "cpu_target_percent" {
  type    = number
  default = 60
}

variable "memory_target_percent" {
  type    = number
  default = 75
}

variable "requests_per_target" {
  type    = number
  default = 500
}
