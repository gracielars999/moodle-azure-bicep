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

var redisName = toLower(take('${prefix}-redis-${uniqueString(resourceGroup().id)}', 63))
var privateDnsZoneName = 'privatelink.redis.cache.windows.net'

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

resource redis 'Microsoft.Cache/redis@2024-11-01' = {
  name: redisName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 1
    }
    redisVersion: '6'
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    redisConfiguration: {}
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
            'redisCache'
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
output primaryKey string = redis.listKeys().primaryKey
output hostname string = redis.properties.hostName
