targetScope = 'resourceGroup'

@description('Prefix used for naming all Moodle resources.')
param prefix string = 'moodle'

@description('Azure region for all regional resources.')
param location string = resourceGroup().location

@description('Administrator username for the VM scale set instances and controller VM.')
param adminUsername string

@description('Administrator password for the VM scale set instances and controller VM.')
@secure()
param adminPassword string

@description('Administrator username for Azure Database for MySQL Flexible Server.')
param mysqlAdminUsername string = 'moodleadmin'

@description('Administrator password for Azure Database for MySQL Flexible Server.')
@secure()
param mysqlAdminPassword string

@description('Custom domain to bind to Azure Front Door, for example moodle.contoso.com.')
param customDomain string

@description('Name of the Moodle database to create in MySQL.')
param moodleDbName string = 'moodle'

@description('Address space for the virtual network, e.g. 10.0.0.0/16.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the frontend subnet (VMSS + ILB + Private Link Service).')
param subnetFrontendPrefix string = '10.0.1.0/24'

@description('Address prefix for the control subnet (Controller VM).')
param subnetControlPrefix string = '10.0.2.0/24'

@description('Address prefix for the data subnet (all private endpoints: MySQL, Redis, Storage, Key Vault).')
param subnetDataPrefix string = '10.0.3.0/24'

@description('Address prefix for the Azure Bastion subnet. Must be /27 or larger.')
param subnetBastionPrefix string = '10.0.5.0/27'

var tags = {
  environment: prefix
  application: 'moodle'
  managedBy: 'bicep'
}

module network './modules/network.bicep' = {
  name: 'network'
  params: {
    prefix: prefix
    location: location
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    subnetFrontendPrefix: subnetFrontendPrefix
    subnetControlPrefix: subnetControlPrefix
    subnetDataPrefix: subnetDataPrefix
    subnetBastionPrefix: subnetBastionPrefix
  }
}

module mysql './modules/mysql.bicep' = {
  name: 'mysql'
  params: {
    prefix: prefix
    location: location
    tags: tags
    vnetId: network.outputs.vnetId
    dataSubnetId: network.outputs.subnetIds.data
    adminUsername: mysqlAdminUsername
    adminPassword: mysqlAdminPassword
    databaseName: moodleDbName
  }
}

module redis './modules/redis.bicep' = {
  name: 'redis'
  params: {
    prefix: prefix
    location: location
    tags: tags
    vnetId: network.outputs.vnetId
    dataSubnetId: network.outputs.subnetIds.data
  }
}

module storage './modules/storage.bicep' = {
  name: 'storage'
  params: {
    prefix: prefix
    location: location
    tags: tags
    vnetId: network.outputs.vnetId
    dataSubnetId: network.outputs.subnetIds.data
  }
}

module compute './modules/compute.bicep' = {
  name: 'compute'
  dependsOn: [
    network
    storage
  ]
  params: {
    prefix: prefix
    location: location
    tags: tags
    adminUsername: adminUsername
    adminPassword: adminPassword
    frontendSubnetId: network.outputs.subnetIds.frontend
    controlSubnetId: network.outputs.subnetIds.control
    privatelinkSubnetId: network.outputs.subnetIds.frontend
    storageAccountName: storage.outputs.storageAccountName
    fileShareName: storage.outputs.fileShareName
    storageAccountKey: storage.outputs.primaryFileKey
  }
}

module keyVault './modules/keyvault.bicep' = {
  name: 'keyvault'
  dependsOn: [
    compute
    mysql
    redis
    storage
  ]
  params: {
    prefix: prefix
    location: location
    tags: tags
    vnetId: network.outputs.vnetId
    dataSubnetId: network.outputs.subnetIds.data
    vmssPrincipalId: compute.outputs.vmssPrincipalId
    controllerPrincipalId: compute.outputs.controllerPrincipalId
    mysqlPassword: mysqlAdminPassword
    redisKey: redis.outputs.primaryKey
    storageKey: storage.outputs.primaryFileKey
  }
}

module frontDoor './modules/frontdoor.bicep' = {
  name: 'frontdoor'
  dependsOn: [
    compute
  ]
  params: {
    prefix: prefix
    location: 'global'
    tags: tags
    customDomain: customDomain
    privateLinkResourceId: compute.outputs.privateLinkServiceId
    originHostName: compute.outputs.loadBalancerPrivateIp
    privateLinkLocation: location
  }
}

module bastion './modules/bastion.bicep' = {
  name: 'bastion'
  dependsOn: [
    network
  ]
  params: {
    prefix: prefix
    location: location
    tags: tags
    bastionSubnetId: network.outputs.subnetIds.bastion
  }
}

output frontDoorEndpoint string = frontDoor.outputs.frontDoorEndpoint
output mysqlFQDN string = mysql.outputs.mysqlFqdn
output storageAccountName string = storage.outputs.storageAccountName
output keyVaultName string = keyVault.outputs.keyVaultName
output vmssName string = compute.outputs.vmssName
output controllerVmName string = compute.outputs.controllerVmName
