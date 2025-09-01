variable "environment" {
  description = "Environment name (production, uat, dr)"
  type        = string
  validation {
    condition     = contains(["production", "uat", "dr"], var.environment)
    error_message = "Environment must be production, uat, or dr."
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
    Project    = "Enterprise-Infrastructure"
    ManagedBy  = "Terraform"
    Owner      = "IT-Operations"
    CostCenter = "IT-001"
  }
}

locals {
  # Map "production" to "prod" for resource naming
  env_short_name = var.environment == "production" ? "prod" : var.environment
  
  env_config = {
    production = {
      vnet_cidr  = "10.0.0.0/16"
      app_subnet = "10.0.1.0/24"
      db_subnet  = "10.0.2.0/24"
      vms = {
        "prod-app" = { type = "application" }
        "prod-db"  = { type = "database" }
      }
    }
    uat = {
      vnet_cidr  = "10.1.0.0/16"
      app_subnet = "10.1.1.0/24"
      db_subnet  = "10.1.2.0/24"
      vms = {
        "uat-app" = { type = "application" }
        "uat-db"  = { type = "database" }
      }
    }
    dr = {
      vnet_cidr  = "10.2.0.0/16"
      app_subnet = "10.2.1.0/24"
      db_subnet  = "10.2.2.0/24"
      vms = {
        "dr-app" = { type = "application" }
        "dr-db"  = { type = "database" }
      }
    }
  }
}
