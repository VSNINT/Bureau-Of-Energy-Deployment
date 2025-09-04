variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["prod", "uat"], var.environment)
    error_message = "Environment must be 'prod' or 'uat'."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralindia"
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureadmin"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project    = "star-shunya"    # CHANGED: surya → shunya
    ManagedBy  = "Terraform"
    Owner      = "IT-Operations"
    CostCenter = "IT-001"
  }
}

variable "tenant_id" {
  description = "Azure Active Directory Tenant ID"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

locals {
  # Environment-specific configuration - RENAMED TO SHUNYA
  env_config = {
    prod = {
      vnet_cidr    = "10.0.0.0/16"
      app_subnet   = "10.0.1.0/24"
      db_subnet    = "10.0.2.0/24"
      vm_sizes     = {
        app = "Standard_D16as_v5"    # PROD UNCHANGED: 16 vCPU, 64GB RAM
        db  = "Standard_E8as_v5"     # PROD UNCHANGED: 8 vCPU, 64GB RAM
      }
      vms = {
        "prod-app" = { type = "application" }
        "prod-db"  = { type = "database" }
      }
    }
    uat = {
      vnet_cidr    = "10.1.0.0/16"
      app_subnet   = "10.1.1.0/24"
      db_subnet    = "10.1.2.0/24"
      vm_sizes     = {
        app = "Standard_D4as_v5"     # UAT: 4 vCPU, 16GB RAM
        db  = "Standard_E4as_v5"     # UAT: 4 vCPU, 32GB RAM
      }
      vms = {
        "uat-app" = { type = "application" }
        "uat-db"  = { type = "database" }
      }
    }
  }

  # Select current environment configuration
  current_env = local.env_config[var.environment]

  # Common tags with environment
  common_tags = merge(var.tags, {
    Environment = var.environment
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    "Created by" = "Deepak"
    "Created on" = "4 Sep 2025"
  })
}
