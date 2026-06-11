@description('Prefix used for naming network resources.')
param prefix string

@description('Azure region for the virtual network and NSGs.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Address space for the virtual network, e.g. 10.0.0.0/16.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the frontend subnet (VMSS + ILB). Must be within vnetAddressPrefix.')
param subnetFrontendPrefix string = '10.0.1.0/24'

@description('Address prefix for the control subnet (Controller VM). Must be within vnetAddressPrefix.')
param subnetControlPrefix string = '10.0.2.0/24'

@description('Address prefix for the data subnet (MySQL, Redis, Storage private endpoints). Must be within vnetAddressPrefix.')
param subnetDataPrefix string = '10.0.3.0/24'

@description('Address prefix for the secrets subnet (Key Vault private endpoint). Must be within vnetAddressPrefix.')
#disable-next-line secure-secrets-in-params
param subnetSecretsPrefix string = '10.0.4.0/24'

@description('Address prefix for Azure Bastion subnet. Must be /27 or larger and within vnetAddressPrefix.')
param subnetBastionPrefix string = '10.0.5.0/27'

@description('Address prefix for the Private Link service subnet (Front Door origin). Must be within vnetAddressPrefix.')
param subnetPrivateLinkPrefix string = '10.0.6.0/24'

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
          sourceAddressPrefix: '10.0.5.0/27'
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
          sourceAddressPrefix: '10.0.5.0/27'
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

resource secretsNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${prefix}-secrets-nsg'
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

resource privateLinkNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${prefix}-privatelink-nsg'
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
        name: 'frontend'
        properties: {
          addressPrefix: subnetFrontendPrefix
          networkSecurityGroup: { id: frontendNsg.id }
        }
      }
      {
        name: 'control'
        properties: {
          addressPrefix: subnetControlPrefix
          networkSecurityGroup: { id: controlNsg.id }
        }
      }
      {
        name: 'data'
        properties: {
          addressPrefix: subnetDataPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: { id: dataNsg.id }
        }
      }
      {
        name: 'secrets'
        properties: {
          addressPrefix: subnetSecretsPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: { id: secretsNsg.id }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: subnetBastionPrefix
          networkSecurityGroup: { id: bastionNsg.id }
        }
      }
      {
        name: 'privatelink'
        properties: {
          addressPrefix: subnetPrivateLinkPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: { id: privateLinkNsg.id }
        }
      }
    ]
  }
}

// Symbolic references to inline subnets for use in output
var subnetFrontend   = vnet.properties.subnets[0].id
var subnetControl    = vnet.properties.subnets[1].id
var subnetData       = vnet.properties.subnets[2].id
var subnetSecrets    = vnet.properties.subnets[3].id
var subnetBastion    = vnet.properties.subnets[4].id
var subnetPrivateLink = vnet.properties.subnets[5].id

output vnetId string = vnet.id
output vnetName string = vnet.name
output subnetIds object = {
  frontend: subnetFrontend
  control: subnetControl
  data: subnetData
  secrets: subnetSecrets
  bastion: subnetBastion
  privatelink: subnetPrivateLink
}
