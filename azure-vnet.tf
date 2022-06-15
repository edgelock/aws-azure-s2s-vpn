variable "azure_client_id" {}
variable "azure_client_secret" {}
variable "tenant_id" {}
variable "azure_subscription_id" {}
variable "location" {
  default = "westus"
}

# initialize connection to azure
provider "azurerm" {
  features {}
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.azure_subscription_id
}

# create a resource group
resource "azurerm_resource_group" "main" {
  name     = "multirg"
  location = var.location
}


# create a vnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet1"
  address_space       = ["172.16.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

# create subnet for Azure Virtual Network Gateway
resource "azurerm_subnet" "subnet" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.16.1.0/24"]
}


# create subnet that connects to AWS VPC
resource "azurerm_subnet" "GatewaySubnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.16.2.0/28"]
}


# create public IP for Virtual Network Gateway
resource "azurerm_public_ip" "gwpip" {
  name                    = "vnetgwpip1"
  location                = var.location
  resource_group_name     = azurerm_resource_group.main.name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30

}

# use data to retrieve public ip since ip address is not available on create
data "azurerm_public_ip" "gwpip" {
  name                = azurerm_public_ip.gwpip.name
  resource_group_name = azurerm_resource_group.main.name
  depends_on = [
    azurerm_public_ip.gwpip,
    # azure PIP's dont allocate until assigned, wait for resource to assign it
    azurerm_virtual_network_gateway.vng
  ]
}


# create the Virtual Network Gateway
resource "azurerm_virtual_network_gateway" "vng" {
  name                = "myvng1"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"


  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.gwpip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.GatewaySubnet.id
  }

}


# create primary local network gateway to connect to AWS tunnel
resource "azurerm_local_network_gateway" "lngw1" {
  name                = "azlngw1"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  gateway_address     = aws_vpn_connection.main.tunnel1_address
  address_space       = [aws_vpc.vpc1.cidr_block]
}

# create secondary local network gateway to connect to AWS tunnel
resource "azurerm_local_network_gateway" "lngw2" {
  name                = "azlngw2"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  gateway_address     = aws_vpn_connection.main.tunnel2_address
  address_space       = [aws_vpc.vpc1.cidr_block]
}


# create primary virtual network gateway connections to AWS with preshared keys
resource "azurerm_virtual_network_gateway_connection" "vngc1" {
  name                = "vngc1"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vng.id
  local_network_gateway_id   = azurerm_local_network_gateway.lngw1.id

  shared_key = aws_vpn_connection.main.tunnel1_preshared_key
}


# create secondary virtual network gateway connections to AWS with preshared keys
resource "azurerm_virtual_network_gateway_connection" "vngc2" {
  name                = "vngc2"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vng.id
  local_network_gateway_id   = azurerm_local_network_gateway.lngw2.id

  shared_key = aws_vpn_connection.main.tunnel2_preshared_key
}


# create route table to forward Azure to AWS vpn gateway

resource "azurerm_route_table" "route" {
  name                = "awsroutetable"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name           = "awsroute"
    address_prefix = aws_vpc.vpc1.cidr_block
    next_hop_type  = "VirtualNetworkGateway"
  }

}