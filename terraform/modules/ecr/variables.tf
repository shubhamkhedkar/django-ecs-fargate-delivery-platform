variable "name" {
  description = "Repository name."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key used to encrypt image layers."
  type        = string
}

variable "keep_tagged_images" {
  description = "How many tagged images to retain (rollback window)."
  type        = number
  default     = 30

  validation {
    condition     = var.keep_tagged_images >= 5
    error_message = "Keep at least 5 tagged images so rollbacks stay possible."
  }
}

variable "untagged_expiry_days" {
  description = "Days before untagged layers are expired."
  type        = number
  default     = 7
}
