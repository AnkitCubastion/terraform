# --- resource group ---

resource "azurerm_resource_group" "arg" {
  name     = "lne"
  location = "West Europe"
}

# --- virtual network ---

resource "azurerm_virtual_network" "avn" {
  name                = "avn"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name
  address_space       = ["10.224.0.0/12"]
}

# --- kubernetes cluster subnet ---

resource "azurerm_subnet" "as-akc" {
  name                 = "as-akc"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.224.0.0/16"]
}

# --- virtual machine subnet ---

resource "azurerm_subnet" "as-avm" {
  name                 = "as-avm"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.225.0.0/16"]
}

# --- container instance subnet ---

resource "azurerm_subnet" "as-acg" {
  name                 = "as-acg"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.226.0.0/16"]

  delegation {
    name = "aciDelegation"
    service_delegation {
      name = "Microsoft.ContainerInstance/containerGroups"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# --- mysql flexible server ---

resource "azurerm_subnet" "as-mfs" {
  name                 = "as-mfs"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.227.0.0/16"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "mfs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# --- application gateway subnet ---

resource "azurerm_subnet" "as-ag" {
  name                 = "as-ag"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.228.0.0/16"]
}

resource "azurerm_private_dns_zone" "apdz" {
  name                = "apdz.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.arg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "apdzvnl" {
  name                  = "apdzvnl.com"
  private_dns_zone_name = azurerm_private_dns_zone.apdz.name
  virtual_network_id    = azurerm_virtual_network.avn.id
  resource_group_name   = azurerm_resource_group.arg.name
}

# --- virtual machine public ip ---

resource "azurerm_public_ip" "api-vm" {
  name                = "avm-pi"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  allocation_method   = "Static"
}

# --- application gateway public ip ---

resource "azurerm_public_ip" "api-ag" {
  name                = "ag-pi"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "ani" {
  name                = "ani"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name

  ip_configuration {
    name                          = "ani-ic"
    subnet_id                     = azurerm_subnet.as-avm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.api-vm.id
  }
}

resource "azurerm_network_security_group" "ansg" {
  name                = "ansg"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name

  security_rule {
    name                       = "port_22"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "asnsga" {
  subnet_id                 = azurerm_subnet.as-avm.id
  network_security_group_id = azurerm_network_security_group.ansg.id
}

##### akc #####

resource "azurerm_kubernetes_cluster" "akc" {
  name                = "akc"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name
  dns_prefix          = "akc-dns"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "standard_d2as_v6"
    vnet_subnet_id = azurerm_subnet.as-akc.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }

  private_cluster_enabled = true
}

##### alvm #####

resource "azurerm_linux_virtual_machine" "alvm" {
  name                = "alvm"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  size                = "Standard_DS1_v2"
  admin_username      = "ankit090701"
  admin_password = "Drowssap@3302"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.ani.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

##### acr #####

resource "azurerm_container_registry" "acr" {
  name                = "acr090701"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  sku                 = "Standard"
}

##### ara (part of acr) #####

resource "azurerm_role_assignment" "ara" {
  principal_id                     = azurerm_kubernetes_cluster.akc.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
}

##### acg ######

resource "azurerm_container_group" "acg" {
  name                = "acg-continst"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name
  ip_address_type     = "Private"
  os_type             = "Linux"

  subnet_ids = [azurerm_subnet.as-acg.id]

  container {
    name   = "react-app"
    image  = "ankit090701/lne-react:latest"
    cpu    = "1"
    memory = "1"

    ports {
      port     = 80
      protocol = "TCP"
    }

    environment_variables = {
      API_BASE_URL = "http://132.220.46.68"
    }
  }

  image_registry_credential {
    server = "index.docker.io"
    username = "ankit090701"
    password = "Cubastion@Ankit"
  }
}

##### mfs #####

resource "azurerm_mysql_flexible_server" "amfs" {
  name                   = "amfs"
  resource_group_name    = azurerm_resource_group.arg.name
  location               = azurerm_resource_group.arg.location
  administrator_login    = "ankit090701"
  administrator_password = "Drowssap@3302"
  backup_retention_days  = 1
  delegated_subnet_id    = azurerm_subnet.as-mfs.id
  private_dns_zone_id    = azurerm_private_dns_zone.apdz.id
  sku_name               = "GP_Standard_D2ds_v4"

  depends_on = [azurerm_private_dns_zone_virtual_network_link.apdzvnl]
}

##### ag #####

resource "azurerm_application_gateway" "aag" {
  name                = "aag"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gip"
    subnet_id = azurerm_subnet.as-ag.id
  }

  frontend_port {
    name = "fp"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "fic"
    public_ip_address_id = azurerm_public_ip.api-ag.id
  }

  backend_address_pool {
    name = "bap"
  }

  backend_http_settings {
    name                  = "bhs"
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "hl"
    frontend_ip_configuration_name = "fic"
    frontend_port_name             = "fp"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rrr"
    priority                   = 101
    rule_type                  = "Basic"
    http_listener_name         = "hl"
    backend_address_pool_name  = "bap"
    backend_http_settings_name = "bhs"
  }
}