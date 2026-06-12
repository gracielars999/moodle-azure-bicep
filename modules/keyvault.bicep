@description('Prefix used for naming Key Vault resources.')
param prefix string

@description('Azure region for Key Vault resources.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Virtual network resource ID used for private DNS linking.')
param vnetId string

@description('Subnet resource ID used for the Key Vault private endpoint (data subnet).')
param dataSubnetId string

@description('Principal ID of the VM scale set system-assigned managed identity.')
param vmssPrincipalId string

@description('Principal ID of the controller VM system-assigned managed identity.')
param controllerPrincipalId string

@description('MySQL administrator password stored as a secret.')
@secure()
param mysqlPassword string

@description('Redis primary access key stored as a secret.')
@secure()
param redisKey string

@description('Azure Files storage account key stored as a secret.')
@secure()
param storageKey string

var keyVaultName = take(replace(toLower('${prefix}-kv-${uniqueString(resourceGroup().id)}'), '-', ''), 24)
var privateDnsZoneName = 'privatelink.vaultcore.azure.net'
var kvSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${prefix}-kv-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${keyVault.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: dataSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVault.name}-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault-zone'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource mysqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-password'
  properties: {
    value: mysqlPassword
  }
}

resource redisKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-key'
  properties: {
    value: redisKey
  }
}

resource storageKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-key'
  properties: {
    value: storageKey
  }
}

resource vmssSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, vmssPrincipalId, kvSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleDefinitionId)
    principalId: vmssPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource controllerSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, controllerPrincipalId, kvSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleDefinitionId)
    principalId: controllerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
