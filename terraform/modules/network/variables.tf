variable "name" {
  description = "Name prefix for network resources."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block (a /16-/20 RFC 1918 range)."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) <= 20
    error_message = "cidr must be a valid IPv4 CIDR of /20 or larger."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across (2-3)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Use 2 or 3 availability zones."
  }
}

variable "region" {
  description = "AWS region, used for VPC endpoint service names."
  type        = string
}

variable "account_id" {
  description = "AWS account ID (confused-deputy guard on the flow-logs role)."
  type        = string
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper) instead of one per AZ (HA)."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Create interface endpoints for ECR, Logs, Secrets Manager, STS plus an S3 gateway endpoint."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key for the flow-log log group."
  type        = string
}

variable "log_retention_days" {
  description = "Flow log retention."
  type        = number
  default     = 365
}
