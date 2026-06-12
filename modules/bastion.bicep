@description('Prefix used for naming Azure Bastion resources.')
param prefix string

@description('Azure region for Bastion resources.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Virtual network resource ID. Developer SKU attaches to the VNet directly — no dedicated subnet needed.')
param vnetId string

// Developer SKU = free tier (no hourly charge).
// Limitations vs Basic/Standard: single concurrent session, no custom ports, no IP-based connect.
// No public IP or AzureBastionSubnet required.
resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: '${prefix}-bastion'
  location: location
  tags: tags
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

output bastionName string = bastion.name
