@description('Prefix used for naming Redis resources.')
param prefix string

@description('Azure region for Redis resources.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Virtual network resource ID used for private DNS linking.')
param vnetId string

@description('Subnet resource ID used for the Redis private endpoint.')
param dataSubnetId string

var redisName = toLower(take('${prefix}-redis-${uniqueString(resourceGroup().id)}', 40))
// Azure Managed Redis uses a region-scoped private DNS zone
var privateDnsZoneName = 'privatelink.${location}.redisenterprise.cache.azure.net'

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${prefix}-redis-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Balanced_B0 = 250 MB RAM, ~$30/month — sufficient for sessions and basic cache at 400 concurrent users
resource redis 'Microsoft.Cache/redisEnterprise@2024-10-01' = {
  name: redisName
  location: location
  tags: tags
  sku: {
    name: 'Balanced_B0'
    capacity: 2
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

// Each cluster must have exactly one database named 'default'
resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2024-10-01' = {
  parent: redis
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    // EnterpriseCluster = single key space; compatible with standard Redis clients (phpredis)
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'VolatileLRU'
    port: 10000
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${redis.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: dataSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${redis.name}-connection'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: [
            'redisEnterprise'
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
        name: 'redis-zone'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output redisId string = redis.id
output redisName string = redis.name
output primaryKey string = redisDatabase.listKeys().primaryKey
output hostname string = redis.properties.hostName
