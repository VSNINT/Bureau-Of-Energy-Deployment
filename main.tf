# main.tf - Updated with OS disk size 256GB and specific storage types

# Data source for client configuration
data "azurerm_client_config" "current" {}

# Local values with updated naming and VM sizes per environment
locals {
  current_env = local.env_config[var.environment]
  common_tags = merge(var.tags, {
    Environment = var.environment
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    Project     = "star-surya"
  })
  
  # VM sizes based on environment and type
  vm_sizes = {
    prod = {
      application = "Standard_D16as_v5"  # 16 vCPUs, 64GB RAM
      database    = "Standard_E16as_v5"  # 16 vCPUs, 128GB RAM (Memory Optimized)
    }
    uat = {
      application = "Standard_D8as_v5"   # 8 vCPUs, 32GB RAM
      database    = "Standard_E8as_v5"   # 8 vCPUs, 64GB RAM (Memory Optimized)
    }
    dr = {
      application = "Standard_D16as_v5"  # 16 vCPUs, 64GB RAM
      database    = "Standard_E16as_v5"  # 16 vCPUs, 128GB RAM (Memory Optimized)
    }
  }
  
  # Disk configurations - All 256GB, HDD except prod-db gets Standard SSD
  disk_configurations = {
    default = {
      storage_account_type = "Standard_LRS"     # Standard HDD
      disk_size_gb         = 256
    }
    prod_db = {
      storage_account_type = "StandardSSD_LRS"  # Standard SSD (only for prod-db)
      disk_size_gb         = 256
    }
  }
}

# Random password generation
resource "random_password" "vm_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
  
  # Add special characters that work well with Windows
  override_special = "!@#$%^&*()_+-=[]{}|;:,.<>?"
}

# Single Resource Group for all environments
resource "azurerm_resource_group" "main" {
  name     = "star-surya-rg"
  location = var.location
  tags     = local.common_tags
}

# Virtual Network per environment
resource "azurerm_virtual_network" "main" {
  name                = "star-surya-${var.environment}-vnet"
  address_space       = [local.current_env.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Application Subnet
resource "azurerm_subnet" "app" {
  name                 = "star-surya-${var.environment}-app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.current_env.app_subnet]
}

# Database Subnet
resource "azurerm_subnet" "db" {
  name                 = "star-surya-${var.environment}-db-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.current_env.db_subnet]
}

# Network Security Group for Application Tier
resource "azurerm_network_security_group" "app" {
  name                = "star-surya-${var.environment}-app-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  security_rule {
    name                       = "HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "FTP"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "21"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "RDP"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Network Security Group for Database Tier
resource "azurerm_network_security_group" "db" {
  name                = "star-surya-${var.environment}-db-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  security_rule {
    name                       = "SQL"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = local.current_env.app_subnet
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "RDP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Subnet and NSG Associations
resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

# Public IP addresses for VMs
resource "azurerm_public_ip" "vm" {
  for_each            = local.current_env.vms
  name                = "star-surya-${each.key}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network Interfaces for VMs
resource "azurerm_network_interface" "vm" {
  for_each            = local.current_env.vms
  name                = "star-surya-${each.key}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.type == "application" ? azurerm_subnet.app.id : azurerm_subnet.db.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm[each.key].id
  }
}

# Windows Virtual Machines with Trusted Launch and Dynamic Sizing and Disk Types
resource "azurerm_windows_virtual_machine" "vm" {
  for_each = local.current_env.vms
  
  name                = "star-surya-${each.key}-vm"
  computer_name       = "ss-${each.key}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = local.vm_sizes[var.environment][each.value.type]
  admin_username      = var.admin_username
  admin_password      = random_password.vm_password.result
  license_type        = "Windows_Server"
  
  # Trusted Launch Configuration
  secure_boot_enabled = true
  vtpm_enabled        = true
  
  # No availability options (no infrastructure redundancy required)
  # availability_set_id is not specified (default: no infrastructure redundancy)
  
  tags = merge(local.common_tags, {
    Role         = each.value.type
    License      = "AHUB-Enabled"
    SecurityType = "TrustedLaunch"
    VMSize       = local.vm_sizes[var.environment][each.value.type]
    DiskType     = each.key == "prod-db" ? "StandardSSD_LRS" : "Standard_LRS"
  })

  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 256  # All VMs get 256GB
    
    # Dynamic storage type: Standard SSD for prod-db, Standard HDD for all others
    storage_account_type = each.key == "prod-db" ? "StandardSSD_LRS" : "Standard_LRS"
    
    # Security settings for Trusted Launch
    security_encryption_type = "VMGuestStateOnly"
  }

  # Dynamic image selection based on VM type - Gen2 images required for Trusted Launch
  source_image_reference {
    publisher = each.value.type == "database" ? "MicrosoftSQLServer" : "MicrosoftWindowsServer"
    offer     = each.value.type == "database" ? "sql2022-ws2022" : "WindowsServer"
    sku       = each.value.type == "database" ? "standard-gen2" : "2022-datacenter-g2"  # Gen2 SKUs
    version   = "latest"
  }

  # Boot diagnostics for troubleshooting
  boot_diagnostics {
    storage_account_uri = null  # Use managed storage
  }
}

# SQL Virtual Machine Configuration (for database VMs only)
resource "azurerm_mssql_virtual_machine" "db" {
  for_each           = { for k, v in local.current_env.vms : k => v if v.type == "database" }
  virtual_machine_id = azurerm_windows_virtual_machine.vm[each.key].id
  sql_license_type   = "AHUB"
  
  # SQL Server connectivity configuration
  sql_connectivity_type = "PRIVATE"
  sql_connectivity_port = 1433
  
  # Explicit dependency to ensure VM is created first
  depends_on = [azurerm_windows_virtual_machine.vm]

  tags = local.common_tags
}

# ==========================================
# OUTPUTS - Updated with disk information
# ==========================================

# VM Admin Password (marked as sensitive)
output "admin_password" {
  value       = random_password.vm_password.result
  sensitive   = true
  description = "VM Administrator Password - use 'terraform output -raw admin_password' to view"
}

# VM Admin Username (non-sensitive)
output "admin_username" {
  value       = var.admin_username
  description = "VM Administrator Username"
}

# VM Sizes and Disk Info per Environment
output "vm_configuration_info" {
  value = {
    for k, v in local.current_env.vms : k => {
      vm_name       = "star-surya-${k}-vm"
      vm_type       = v.type
      vm_size       = local.vm_sizes[var.environment][v.type]
      disk_size_gb  = 256
      disk_type     = k == "prod-db" ? "StandardSSD_LRS" : "Standard_LRS"
      security_type = "Trusted Launch"
      availability  = "No infrastructure redundancy"
    }
  }
  description = "VM configuration and disk information"
}

# Complete Resource Summary (marked as sensitive due to password)
output "resource_summary" {
  value = {
    resource_group   = azurerm_resource_group.main.name
    location         = var.location
    environment      = var.environment
    vnet_name        = azurerm_virtual_network.main.name
    vnet_cidr        = local.current_env.vnet_cidr
    app_subnet       = local.current_env.app_subnet
    db_subnet        = local.current_env.db_subnet
    vm_count         = length(local.current_env.vms)
    vm_sizes         = { for k, v in local.current_env.vms : k => local.vm_sizes[var.environment][v.type] }
    disk_sizes       = { for k, v in local.current_env.vms : k => "256GB" }
    disk_types       = { for k, v in local.current_env.vms : k => (k == "prod-db" ? "Standard SSD" : "Standard HDD") }
    security_type    = "Trusted Launch"
    license_type     = "Azure Hybrid Use Benefit (A-HUB)"
    admin_username   = var.admin_username
    admin_password   = random_password.vm_password.result
    deployment_time  = timestamp()
  }
  sensitive   = true
  description = "Complete summary of deployed resources including credentials"
}

# VM Public IP Addresses (non-sensitive)
output "vm_public_ips" {
  value = {
    for k, v in azurerm_public_ip.vm : k => v.ip_address
  }
  description = "Public IP addresses of all VMs"
}

# VM Private IP Addresses (non-sensitive)
output "vm_private_ips" {
  value = {
    for k, v in azurerm_network_interface.vm : k => v.private_ip_address
  }
  description = "Private IP addresses of all VMs"
}

# VM Connection Information (non-sensitive)
output "vm_connection_info" {
  value = {
    for k, v in azurerm_public_ip.vm : k => {
      public_ip     = v.ip_address
      private_ip    = azurerm_network_interface.vm[k].private_ip_address
      rdp_command   = "mstsc /v:${v.ip_address}"
      vm_type       = local.current_env.vms[k].type
      vm_name       = "star-surya-${k}-vm"
      vm_size       = local.vm_sizes[var.environment][local.current_env.vms[k].type]
      disk_size     = "256GB"
      disk_type     = k == "prod-db" ? "Standard SSD LRS" : "Standard HDD LRS"
      security_type = "Trusted Launch"
    }
  }
  description = "Complete connection information for all VMs"
}

# Resource Group Information (non-sensitive)
output "resource_group_info" {
  value = {
    name     = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
    id       = azurerm_resource_group.main.id
  }
  description = "Resource group information"
}

# Network Information (non-sensitive)
output "network_info" {
  value = {
    vnet_name    = azurerm_virtual_network.main.name
    vnet_cidr    = local.current_env.vnet_cidr
    app_subnet   = local.current_env.app_subnet
    db_subnet    = local.current_env.db_subnet
  }
  description = "Network configuration information"
}

# Quick Access Summary (marked as sensitive due to password)
output "quick_access" {
  value = <<-EOT
    ====================================
    🔐 STAR-SURYA ${upper(var.environment)} CREDENTIALS
    ====================================
    Username: ${var.admin_username}
    Password: ${random_password.vm_password.result}
    
    ====================================
    🌐 RDP CONNECTIONS
    ====================================
    ${join("\n    ", [for k, v in azurerm_public_ip.vm : "star-surya-${k}-vm (${local.vm_sizes[var.environment][local.current_env.vms[k].type]}, 256GB ${k == "prod-db" ? "Standard SSD" : "Standard HDD"}): mstsc /v:${v.ip_address}"])}
    
    ====================================
    📊 DEPLOYMENT SUMMARY
    ====================================
    Project: star-surya
    Environment: ${var.environment}
    Resource Group: ${azurerm_resource_group.main.name}
    VNet: ${azurerm_virtual_network.main.name}
    Location: ${var.location}
    Security Type: Trusted Launch
    VMs Deployed: ${length(local.current_env.vms)}
    
    ====================================
    💻 VM SPECIFICATIONS & DISKS
    ====================================
    ${join("\n    ", [for k, v in local.current_env.vms : "${k}: ${local.vm_sizes[var.environment][v.type]} | 256GB ${k == "prod-db" ? "Standard SSD LRS" : "Standard HDD LRS"} | ${v.type == "application" ? "General Purpose" : "Memory Optimized"}"])}
  EOT
  sensitive   = true
  description = "Quick access summary with all essential information including disk details"
}
