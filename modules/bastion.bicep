@description('Prefix used for naming Azure Bastion resources.')
param prefix string

@description('Azure region for Bastion resources.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Subnet resource ID of AzureBastionSubnet.')
param bastionSubnetId string

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${prefix}-bastion-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: '${prefix}-bastion'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: bastionSubnetId
          }
        }
      }
    ]
  }
}

output bastionName string = bastion.name
