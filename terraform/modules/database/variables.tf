variable "name" {
  description = "Identifier prefix for the database."
  type        = string
}

variable "partition" {
  description = "AWS partition (aws, aws-cn, aws-us-gov)."
  type        = string
  default     = "aws"
}

variable "subnet_ids" {
  description = "Isolated database subnets (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS needs subnets in at least two availability zones."
  }
}

variable "security_group_id" {
  description = "Security group that only admits the app tier on 5432."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for storage, Performance Insights and the managed master secret."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL version (major or major.minor)."
  type        = string
  default     = "17"

  validation {
    condition     = tonumber(split(".", var.engine_version)[0]) >= 15
    error_message = "Use PostgreSQL 15 or newer."
  }
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)."
  type        = number
  default     = 100
}

variable "multi_az" {
  type    = bool
  default = true
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "backup_retention_days" {
  type    = number
  default = 14

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Keep 7-35 days of automated backups."
  }
}

variable "db_name" {
  type    = string
  default = "ledger"
}

variable "username" {
  type    = string
  default = "ledger_admin"
}

variable "slow_query_ms" {
  description = "Log statements slower than this many milliseconds."
  type        = number
  default     = 500
}
