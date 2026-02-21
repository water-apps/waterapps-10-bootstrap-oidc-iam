variable "aws_region" {
  description = "AWS region — ap-southeast-2 for data sovereignty (Australian clients)"
  type        = string
  default     = "ap-southeast-2"
}

variable "project" {
  description = "Project name used in resource naming and IAM scope prefixes"
  type        = string
  default     = "waterapps"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "github_org" {
  description = "GitHub organisation or personal account that owns the repos"
  type        = string
  default     = "vkaushik13"
}

variable "github_repos" {
  description = "GitHub repos authorised to assume the deploy role via OIDC"
  type        = list(string)
  default     = ["waterapps-contact-form"]

  validation {
    condition     = length(var.github_repos) > 0
    error_message = "At least one GitHub repo must be specified."
  }
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "WaterApps"
    Component   = "Bootstrap"
    Environment = "prod"
    ManagedBy   = "terraform"
    Owner       = "waterapps"
    CostCenter  = "Platform"
  }
}
