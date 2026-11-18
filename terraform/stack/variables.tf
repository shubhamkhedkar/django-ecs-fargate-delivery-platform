variable "project" {
  description = "Short service name used in resource names."
  type        = string
  default     = "release-ledger"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "project must be 3-21 chars of lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "shubham-khedkar"
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway (cheaper, not AZ-resilient)."
  type        = bool
  default     = false
}

variable "app_domain" {
  description = "Public hostname for the app (Route 53 / DNS is managed outside this stack)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.app_domain))
    error_message = "app_domain must be a hostname such as ledger.example.com."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN covering app_domain (same region as the ALB)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.alb_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "alb_ingress_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "image_tag" {
  description = "Immutable image tag (git SHA) deployed by the initial task definition."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag must be a git SHA (7-40 hex chars); mutable tags such as 'latest' are not allowed."
  }
}

variable "task_cpu" {
  type    = number
  default = 512
}

variable "task_memory" {
  type    = number
  default = 1024
}

variable "cpu_architecture" {
  type    = string
  default = "X86_64"
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6

  validation {
    condition     = var.max_capacity <= 50
    error_message = "max_capacity above 50 needs a deliberate review."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_engine_version" {
  type    = string
  default = "17"
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "deletion_protection" {
  description = "Protect the ALB and RDS instance from accidental deletion."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "alarm_email" {
  description = "Optional address subscribed to the alarm topic (confirm via email)."
  type        = string
  default     = ""
}
