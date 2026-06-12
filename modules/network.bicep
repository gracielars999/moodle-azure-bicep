@description('Prefix used for naming network resources.')
param prefix string

@description('Azure region for the virtual network and NSGs.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Address space for the virtual network, e.g. 10.0.0.0/16.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the frontend subnet (VMSS + ILB + Private Link Service). Must be within vnetAddressPrefix.')
param subnetFrontendPrefix string = '10.0.1.0/24'

@description('Address prefix for the control subnet (Controller VM). Must be within vnetAddressPrefix.')
param subnetControlPrefix string = '10.0.2.0/24'

@description('Address prefix for the data subnet (all private endpoints: MySQL, Storage, Key Vault). Must be within vnetAddressPrefix.')
param subnetDataPrefix string = '10.0.3.0/24'

var vnetName = '${prefix}-vnet'

resource frontendNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${prefix}-frontend-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-FrontDoor-HTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-FrontDoor-HTTPS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          destinationAddressPrefix: '*'
        }
      }
      {
        // Developer Bastion routes traffic from within the VNet (no dedicated subnet)
        name: 'Allow-Bastion-RDP'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource controlNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${prefix}-control-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Bastion-RDP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource dataNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${prefix}-data-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    // All subnets defined inline — avoids AnotherOperationInProgress errors.
    // Azure allows only one concurrent write per VNet; separate child subnet resources
    // deployed in parallel will race and fail. Inline = single API call.
    subnets: [
      {
        // Hosts VMSS nodes, Internal Load Balancer, and Private Link Service NAT IPs.
        // privateLinkServiceNetworkPolicies must be Disabled for PLS to function.
        name: 'frontend'
        properties: {
          addressPrefix: subnetFrontendPrefix
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: { id: frontendNsg.id }
        }
      }
      {
        // Hosts the Controller VM (code deploy, cron, accessed via Bastion Developer).
        name: 'control'
        properties: {
          addressPrefix: subnetControlPrefix
          networkSecurityGroup: { id: controlNsg.id }
        }
      }
      {
        // Hosts all private endpoints: MySQL, Storage, and Key Vault.
        name: 'data'
        properties: {
          addressPrefix: subnetDataPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: { id: dataNsg.id }
        }
      }
    ]
  }
}

// Symbolic references to inline subnets (3 subnets, indices 0-2)
var subnetFrontend = vnet.properties.subnets[0].id
var subnetControl  = vnet.properties.subnets[1].id
var subnetData     = vnet.properties.subnets[2].id

output vnetId string = vnet.id
output vnetName string = vnet.name
output subnetIds object = {
  frontend: subnetFrontend
  control: subnetControl
  data: subnetData
}
