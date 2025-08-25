locals {
  current_env = local.env_config[var.environment]
  common_tags = merge(var.tags, {
    Environment = var.environment
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })

  vm_size        = "Standard_D2as_v5"
  os_disk_size_gb = 128
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.environment}-enterprise-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.environment}-vnet"
  address_space       = [local.current_env.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "app" {
  name                  = "${var.environment}-app-subnet"
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_name  = azurerm_virtual_network.main.name
  address_prefixes      = [local.current_env.app_subnet]
}

resource "azurerm_subnet" "db" {
  name                  = "${var.environment}-db-subnet"
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_name  = azurerm_virtual_network.main.name
  address_prefixes      = [local.current_env.db_subnet]
}


resource "azurerm_network_security_group" "app" {
  name                = "${var.environment}-app-nsg"
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

resource "azurerm_network_security_group" "db" {
  name                = "${var.environment}-db-nsg"
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

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

resource "azurerm_public_ip" "vm" {
  for_each = local.current_env.vms
  name                = "${each.key}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "vm" {
  for_each = local.current_env.vms
  name                = "${each.key}-nic"
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

# Important: This assumes "sql2022-windows2025" exists. If not, use "sql2022-windows2022".
resource "azurerm_windows_virtual_machine" "vm" {
  for_each            = local.current_env.vms

  name                = each.key
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = local.vm_size
  admin_username      = var.admin_username
  admin_password      = random_password.vm_password.result
  license_type        = "Windows_Server"

  tags = merge(local.common_tags, {
    Role    = each.value.type
    License = "AHUB-Enabled"
  })

  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = local.os_disk_size_gb
  }

  # Differentiate image for DB VMs (SQL) vs. others
  source_image_reference {
    publisher = each.value.type == "database" ? "MicrosoftSQLServer" : "MicrosoftWindowsServer"
    offer     = each.value.type == "database" ? "sql2022-windows2025" : "WindowsServer"
    # If "sql2022-windows2025" not available, fallback to "sql2022-windows2022"
    sku       = each.value.type == "database" ? "Standard" : "2025-datacenter"
    version   = "latest"
  }
}

resource "azurerm_mssql_virtual_machine" "db" {
  for_each           = { for k, v in local.current_env.vms : k => v if v.type == "database" }
  virtual_machine_id = azurerm_windows_virtual_machine.vm[each.key].id
  sql_license_type   = "AHUB"
}

output "resource_summary" {
  value = {
    resource_group = azurerm_resource_group.main.name
    location       = var.location
    environment    = var.environment
    vnet_cidr      = local.current_env.vnet_cidr
    app_subnet     = local.current_env.app_subnet
    db_subnet      = local.current_env.db_subnet
    vm_count       = length(local.current_env.vms)
    vm_size        = local.vm_size
    os_disk_size   = "${local.os_disk_size_gb}GB"
    license_type   = "Azure Hybrid Use Benefit (A-HUB)"
    admin_password = random_password.vm_password.result
  }
  sensitive = true
}

output "vm_public_ips" {
  value = {
    for k, v in azurerm_public_ip.vm : k => v.ip_address
  }
}

output "vm_private_ips" {
  value = {
    for k, v in azurerm_network_interface.vm : k => v.private_ip_address
  }
}
