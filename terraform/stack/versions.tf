terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Configure your own state bucket before the first real plan, e.g.:
  # backend "s3" {
  #   bucket       = "<your-state-bucket>"
  #   key          = "release-ledger/prod/terraform.tfstate"
  #   region       = "ap-south-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "django-ecs-fargate-delivery-platform"
      Service     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}
