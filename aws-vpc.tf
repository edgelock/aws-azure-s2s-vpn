variable "aws_access_key" {}
variable "aws_secret_key" {}

variable "region" {
  default = "us-east-1"
}

# initialize connection to aws
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}


# add a new VPC
resource "aws_vpc" "vpc1" {
  cidr_block = "192.168.0.0/16"
  tags = {
    Name = "S2S VPC"
  }
}

# create a subnet within VPC
resource "aws_subnet" "main" {
  vpc_id = aws_vpc.vpc1.id

  # use a /20 block for subnet
  cidr_block = cidrsubnet(aws_vpc.vpc1.cidr_block, 4, 1)
}

# AWS customer gateway
resource "aws_customer_gateway" "main" {
  bgp_asn    = 65000
  ip_address = data.azurerm_public_ip.gwpip.ip_address
  type       = "ipsec.1"

  tags = {
    Name = "main-customer-gateway"
  }
}

# create AWS vpn gateway
resource "aws_vpn_gateway" "vpn_gw" {
  vpc_id = aws_vpc.vpc1.id
  tags = {
    Name = "main"
  }
}

# create vpn connection
resource "aws_vpn_connection" "main" {
  vpn_gateway_id      = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id = aws_customer_gateway.main.id
  type                = "ipsec.1"
  static_routes_only  = true
}

# create vpn connection route
resource "aws_vpn_connection_route" "azure" {
  destination_cidr_block = azurerm_subnet.subnet.address_prefixes.0
  vpn_connection_id      = aws_vpn_connection.main.id
}

# create routing tables to forward AWS to Azure Vnet Gateway 
resource "aws_route" "azureroute" {
  route_table_id         = aws_vpc.vpc1.main_route_table_id
  destination_cidr_block = azurerm_subnet.subnet.address_prefixes.0
  gateway_id             = aws_vpn_gateway.vpn_gw.id
}
