# main.tf - CORRECTED version with SHUNYA naming (NO moved blocks needed)
data "azurerm_client_config" "current" {}

# Random password generation
resource "random_password" "vm_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
  override_special = "!@#$%^&*()_+-=[]{}|;:,.<>?"
}

# SEPARATE RESOURCE GROUPS
resource "azurerm_resource_group" "uat" {
  count    = var.environment == "uat" ? 1 : 0
  name     = "srs-uat-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "prod" {
  count    = var.environment == "prod" ? 1 : 0
  name     = "srs-prod-rg"
  location = var.location
  tags     = local.common_tags
}

# Local values for dynamic resource group selection
locals {
  resource_group_name = var.environment == "prod" ? "srs-prod-rg" : "srs-uat-rg"
  resource_group_obj  = var.environment == "prod" ? azurerm_resource_group.prod[0] : azurerm_resource_group.uat[0]
}

# Virtual Network - RENAMED TO SHUNYA
resource "azurerm_virtual_network" "main" {
  name                = "star-shunya-${var.environment}-vnet"
  address_space       = [local.current_env.vnet_cidr]
  location            = local.resource_group_obj.location
  resource_group_name = local.resource_group_obj.name
  tags                = local.common_tags
}

# Application Subnet - RENAMED TO SHUNYA
resource "azurerm_subnet" "app" {
  name                 = "star-shunya-${var.environment}-app-subnet"
  resource_group_name  = local.resource_group_obj.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.current_env.app_subnet]
}

# Database Subnet - RENAMED TO SHUNYA
resource "azurerm_subnet" "db" {
  name                 = "star-shunya-${var.environment}-db-subnet"
  resource_group_name  = local.resource_group_obj.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.current_env.db_subnet]
}

# Network Security Group for Application Tier - RENAMED TO SHUNYA
resource "azurerm_network_security_group" "app" {
  name                = "star-shunya-${var.environment}-app-nsg"
  location            = local.resource_group_obj.location
  resource_group_name = local.resource_group_obj.name
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

# Network Security Group for Database Tier - RENAMED TO SHUNYA
resource "azurerm_network_security_group" "db" {
  name                = "star-shunya-${var.environment}-db-nsg"
  location            = local.resource_group_obj.location
  resource_group_name = local.resource_group_obj.name
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

# Public IP addresses for VMs - RENAMED TO SHUNYA
resource "azurerm_public_ip" "vm" {
  for_each            = local.current_env.vms
  name                = "star-shunya-${each.key}-pip"
  location            = local.resource_group_obj.location
  resource_group_name = local.resource_group_obj.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network Interfaces for VMs - RENAMED TO SHUNYA
resource "azurerm_network_interface" "vm" {
  for_each            = local.current_env.vms
  name                = "star-shunya-${each.key}-nic"
  location            = local.resource_group_obj.location
  resource_group_name = local.resource_group_obj.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.type == "application" ? azurerm_subnet.app.id : azurerm_subnet.db.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm[each.key].id
  }
}

# ===== MANAGED DATA DISKS (256GB HDD for each VM) - RENAMED TO SHUNYA =====
resource "azurerm_managed_disk" "data_disk" {
  for_each = local.current_env.vms
  
  name                 = "star-shunya-${each.key}-data-disk"
  location             = local.resource_group_obj.location
  resource_group_name  = local.resource_group_obj.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 256
  
  tags = merge(local.common_tags, {
    Purpose = "Data Storage"
    VMName  = "star-shunya-${each.key}-vm"
  })
}

# Windows Virtual Machines - RENAMED TO SHUNYA
resource "azurerm_windows_virtual_machine" "vm" {
  for_each = local.current_env.vms
  
  name                = "star-shunya-${each.key}-vm"
  computer_name       = "ss-${each.key}-vm"
  location            = local.resource_group_obj.location
  resource_group_name = local.resource_group_obj.name
  size                = local.current_env.vm_sizes[each.value.type == "application" ? "app" : "db"]
  admin_username      = var.admin_username
  admin_password      = random_password.vm_password.result
  license_type        = "Windows_Server"
  
  tags = merge(local.common_tags, {
    Role   = each.value.type
    VMSize = local.current_env.vm_sizes[each.value.type == "application" ? "app" : "db"]
  })

  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id,
  ]

  # CONDITIONAL OS DISK: Standard SSD only for prod database VM
  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 256
    storage_account_type = (var.environment == "prod" && each.key == "prod-db") ? "StandardSSD_LRS" : "Standard_LRS"
  }

  source_image_reference {
    publisher = each.value.type == "database" ? "MicrosoftSQLServer" : "MicrosoftWindowsServer"
    offer     = each.value.type == "database" ? "sql2022-ws2022" : "WindowsServer"
    sku       = each.value.type == "database" ? "standard-gen2" : "2022-datacenter"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }
}

# ===== DATA DISK ATTACHMENTS =====
resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attachment" {
  for_each = local.current_env.vms
  
  managed_disk_id    = azurerm_managed_disk.data_disk[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.vm[each.key].id
  lun                = 0
  caching            = "ReadWrite"
}

# SQL Virtual Machine Configuration
resource "azurerm_mssql_virtual_machine" "db" {
  for_each           = { for k, v in local.current_env.vms : k => v if v.type == "database" }
  virtual_machine_id = azurerm_windows_virtual_machine.vm[each.key].id
  sql_license_type   = "AHUB"
  sql_connectivity_type = "PRIVATE"
  sql_connectivity_port = 1433
  depends_on = [azurerm_windows_virtual_machine.vm]
  tags = local.common_tags
}

# ==========================================
# OUTPUTS (UPDATED WITH SHUNYA NAMING)
# ==========================================
output "admin_password" {
  value       = random_password.vm_password.result
  sensitive   = true
  description = "VM Administrator Password"
}

output "admin_username" {
  value       = var.admin_username
  description = "VM Administrator Username"
}

output "resource_group_name" {
  value       = local.resource_group_name
  description = "Resource group name for this environment"
}

output "vm_public_ips" {
  value = {
    for k, v in azurerm_public_ip.vm : k => v.ip_address
  }
  description = "Public IP addresses of all VMs"
}

output "vm_private_ips" {
  value = {
    for k, v in azurerm_network_interface.vm : k => v.private_ip_address
  }
  description = "Private IP addresses of all VMs"
}

output "data_disk_info" {
  value = {
    for k, v in azurerm_managed_disk.data_disk : k => {
      name     = v.name
      size_gb  = v.disk_size_gb
      type     = v.storage_account_type
      vm_name  = "star-shunya-${k}-vm"
    }
  }
  description = "Information about data disks attached to VMs"
}

output "vm_connection_info" {
  value = {
    for k, v in azurerm_public_ip.vm : k => {
      public_ip      = v.ip_address
      private_ip     = azurerm_network_interface.vm[k].private_ip_address
      rdp_command    = "mstsc /v:${v.ip_address}"
      vm_type        = local.current_env.vms[k].type
      vm_name        = "star-shunya-${k}-vm"
      vm_size        = local.current_env.vm_sizes[local.current_env.vms[k].type == "application" ? "app" : "db"]
      resource_group = local.resource_group_name
      os_disk_type   = (var.environment == "prod" && k == "prod-db") ? "StandardSSD_LRS (Standard SSD)" : "Standard_LRS (HDD)"
      data_disk      = "star-shunya-${k}-data-disk (256GB HDD)"
    }
  }
  description = "Complete connection information for all VMs including disk info"
}

output "quick_access" {
  value = <<-EOT
    ====================================
    🔐 STAR-SHUNYA ${upper(var.environment)} ENVIRONMENT
    ====================================
    Resource Group: ${local.resource_group_name}
    Username: ${var.admin_username}
    Password: ${random_password.vm_password.result}
    
    ====================================
    🌐 RDP CONNECTIONS
    ====================================
    ${join("\n    ", [for k, v in azurerm_public_ip.vm : "star-shunya-${k}-vm: mstsc /v:${v.ip_address}"])}
    
    ====================================
    💾 DISK CONFIGURATION
    ====================================
    ${join("\n    ", [for k, v in azurerm_managed_disk.data_disk : "${k}: OS Disk ${(var.environment == "prod" && k == "prod-db") ? "Standard SSD" : "Standard HDD"} + Data Disk ${v.disk_size_gb}GB HDD"])}
    
    ====================================
    📊 DEPLOYMENT SUMMARY
    ====================================
    Environment: ${var.environment}
    Resource Group: ${local.resource_group_name}
    VNet: ${azurerm_virtual_network.main.name}
    Location: ${var.location}
    VMs Deployed: ${length(local.current_env.vms)}
    Data Disks: ${length(local.current_env.vms)} x 256GB HDD
    Special: prod-db has Standard SSD OS disk (StandardSSD_LRS)
    ====================================
  EOT
  sensitive   = true
  description = "Quick access summary with complete disk configuration"
}
