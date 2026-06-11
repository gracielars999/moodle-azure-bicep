@description('Prefix used for naming MySQL resources.')
param prefix string

@description('Azure region for MySQL resources.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Virtual network resource ID used for private DNS linking.')
param vnetId string

@description('Subnet resource ID used for the MySQL private endpoint.')
param dataSubnetId string

@description('Administrator username for Azure Database for MySQL Flexible Server.')
param adminUsername string

@description('Administrator password for Azure Database for MySQL Flexible Server.')
@secure()
param adminPassword string

@description('Name of the Moodle database to create.')
param databaseName string

var mysqlServerName = toLower(take('${prefix}-mysql-${uniqueString(resourceGroup().id)}', 63))
var privateDnsZoneName = 'privatelink.mysql.database.azure.com'

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${prefix}-mysql-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: mysqlServerName
  location: location
  tags: tags
  sku: {
    name: 'Standard_D2ds_v4'
    tier: 'GeneralPurpose'
  }
  properties: {
    version: '8.0.21'
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    availabilityZone: '1'
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: '2'
    }
    network: {
      publicNetworkAccess: 'Disabled'
    }
    storage: {
      autoGrow: 'Enabled'
      storageSizeGB: 128
    }
  }
}

resource requireSecureTransport 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-30' = {
  parent: mysqlServer
  name: 'require_secure_transport'
  properties: {
    source: 'user-override'
    value: 'ON'
  }
}

resource minimumTlsVersion 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-30' = {
  parent: mysqlServer
  name: 'tls_version'
  properties: {
    source: 'user-override'
    value: 'TLSv1.2'
  }
}

resource moodleDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2023-12-30' = {
  parent: mysqlServer
  name: databaseName
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_unicode_ci'
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${mysqlServer.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: dataSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${mysqlServer.name}-connection'
        properties: {
          privateLinkServiceId: mysqlServer.id
          groupIds: [
            'mysqlserver'
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
        name: 'mysql-zone'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output mysqlServerId string = mysqlServer.id
output mysqlServerName string = mysqlServer.name
output mysqlFqdn string = mysqlServer.properties.fullyQualifiedDomainName
output privateEndpointId string = privateEndpoint.id
