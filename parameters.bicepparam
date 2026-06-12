using './main.bicep'

param prefix = 'moodle'
param location = 'eastus'
param adminUsername = '<vm-admin-username>'
param adminPassword = '<vm-admin-password>'
param mysqlAdminUsername = 'moodleadmin'
param mysqlAdminPassword = '<mysql-admin-password>'
param customDomain = 'moodle.contoso.com'
param moodleDbName = 'moodle'

// Optional: override VNet and subnet CIDRs if they conflict with your existing network
// param vnetAddressPrefix      = '10.0.0.0/16'
// param subnetFrontendPrefix   = '10.0.1.0/24'  // VMSS + ILB + Private Link Service
// param subnetControlPrefix    = '10.0.2.0/24'  // Controller VM
// param subnetDataPrefix       = '10.0.3.0/24'  // All private endpoints (MySQL, Redis, Storage, Key Vault)
// param subnetBastionPrefix    = '10.0.5.0/27'  // Azure Bastion (must be /27 or larger)
