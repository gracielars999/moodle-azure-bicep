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

@description('Address prefix for the data subnet (all private endpoints: MySQL, Redis, Storage, Key Vault). Must be within vnetAddressPrefix.')
param subnetDataPrefix string = '10.0.3.0/24'

@description('Address prefix for Azure Bastion subnet. Must be /27 or larger and within vnetAddressPrefix.')
param subnetBastionPrefix string = '10.0.5.0/27'

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
        name: 'Allow-Bastion-RDP'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: subnetBastionPrefix
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
          sourceAddressPrefix: subnetBastionPrefix
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

resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${prefix}-bastion-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Internet-443-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-GatewayManager-443-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-443-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-VNet-8080-5701-Inbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
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
      {
        name: 'Allow-VNet-22-3389-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-VNet-8080-5701-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-AzureCloud-443-Outbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
      {
        name: 'Allow-Internet-80-Outbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
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
        // Hosts the Controller VM (code deploy, cron, RDP jump target via Bastion).
        name: 'control'
        properties: {
          addressPrefix: subnetControlPrefix
          networkSecurityGroup: { id: controlNsg.id }
        }
      }
      {
        // Hosts all private endpoints: MySQL, Redis, Storage, and Key Vault.
        // Consolidating endpoints into one subnet reduces cost and simplifies DNS.
        name: 'data'
        properties: {
          addressPrefix: subnetDataPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: { id: dataNsg.id }
        }
      }
      {
        // Required name — Azure Bastion will not deploy to a differently named subnet.
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: subnetBastionPrefix
          networkSecurityGroup: { id: bastionNsg.id }
        }
      }
    ]
  }
}

// Symbolic references to inline subnets (4 subnets, indices 0-3)
var subnetFrontend = vnet.properties.subnets[0].id
var subnetControl  = vnet.properties.subnets[1].id
var subnetData     = vnet.properties.subnets[2].id
var subnetBastion  = vnet.properties.subnets[3].id

output vnetId string = vnet.id
output vnetName string = vnet.name
output subnetIds object = {
  frontend: subnetFrontend
  control: subnetControl
  data: subnetData
  bastion: subnetBastion
}
