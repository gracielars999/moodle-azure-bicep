@description('Prefix used for naming compute resources.')
param prefix string

@description('Azure region for compute resources.')
param location string

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Administrator username for the VM scale set instances and controller VM.')
param adminUsername string

@description('Administrator password for the VM scale set instances and controller VM.')
@secure()
param adminPassword string

@description('Subnet resource ID for the frontend tier.')
param frontendSubnetId string

@description('Subnet resource ID for the control tier.')
param controlSubnetId string

@description('Subnet resource ID for the Private Link Service NAT IP configuration.')
param privatelinkSubnetId string

@description('Storage account name hosting the Premium Azure Files share.')
param storageAccountName string

@description('Azure Files share name mounted by Moodle nodes and the controller VM.')
param fileShareName string

@description('Storage account key used by setup scripts to mount Azure Files.')
@secure()
param storageAccountKey string

var loadBalancerName = '${prefix}-ilb'
var vmssName = '${prefix}-vmss'
var controllerVmName = '${prefix}-controller-vm'
var controllerNicName = '${prefix}-controller-nic'
var privateLinkServiceName = '${prefix}-pls'
var loadBalancerPrivateIp = '10.0.1.10'
var privateLinkNatIp = '10.0.1.20'
var loadBalancerFrontendId = resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'frontend')
var loadBalancerBackendPoolId = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backendpool')
var loadBalancerProbeId = resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'http-probe')
var nodeScriptBase64 = base64(loadTextContent('../scripts/setup-moodle-node.ps1'))
var controllerScriptBase64 = base64(loadTextContent('../scripts/setup-controller.ps1'))
var vmssCommand = 'powershell -ExecutionPolicy Bypass -Command "$env:MOODLE_STORAGE_ACCOUNT=`"${storageAccountName}`"; $env:MOODLE_FILE_SHARE=`"${fileShareName}`"; $env:MOODLE_STORAGE_KEY=`"${storageAccountKey}`"; $script=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`"${nodeScriptBase64}`")); Invoke-Expression $script"'
var controllerCommand = 'powershell -ExecutionPolicy Bypass -Command "$env:MOODLE_STORAGE_ACCOUNT=`"${storageAccountName}`"; $env:MOODLE_FILE_SHARE=`"${fileShareName}`"; $env:MOODLE_STORAGE_KEY=`"${storageAccountKey}`"; $script=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`"${controllerScriptBase64}`")); Invoke-Expression $script"'

resource loadBalancer 'Microsoft.Network/loadBalancers@2024-01-01' = {
  name: loadBalancerName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend'
        properties: {
          privateIPAddress: loadBalancerPrivateIp
          privateIPAllocationMethod: 'Static'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: frontendSubnetId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backendpool'
      }
    ]
    probes: [
      {
        name: 'http-probe'
        properties: {
          protocol: 'Http'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
          requestPath: '/login/index.php'
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-rule'
        properties: {
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 15
          enableFloatingIP: false
          disableOutboundSnat: true
          loadDistribution: 'Default'
          frontendIPConfiguration: {
            id: loadBalancerFrontendId
          }
          backendAddressPool: {
            id: loadBalancerBackendPoolId
          }
          probe: {
            id: loadBalancerProbeId
          }
        }
      }
      {
        name: 'https-rule'
        properties: {
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          idleTimeoutInMinutes: 15
          enableFloatingIP: false
          disableOutboundSnat: true
          loadDistribution: 'Default'
          frontendIPConfiguration: {
            id: loadBalancerFrontendId
          }
          backendAddressPool: {
            id: loadBalancerBackendPoolId
          }
          probe: {
            id: loadBalancerProbeId
          }
        }
      }
    ]
  }
}

resource privateLinkService 'Microsoft.Network/privateLinkServices@2024-01-01' = {
  name: privateLinkServiceName
  location: location
  tags: tags
  dependsOn: [loadBalancer] // ILB must exist before PLS can reference its frontend IP config
  properties: {
    autoApproval: {
      subscriptions: []
    }
    enableProxyProtocol: false
    fqdns: []
    ipConfigurations: [
      {
        name: 'nat-ip'
        properties: {
          primary: true
          privateIPAddress: privateLinkNatIp
          privateIPAllocationMethod: 'Static'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: privatelinkSubnetId
          }
        }
      }
    ]
    loadBalancerFrontendIpConfigurations: [
      {
        id: loadBalancerFrontendId
      }
    ]
    visibility: {
      subscriptions: []
    }
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: vmssName
  location: location
  tags: tags
  sku: {
    // D2s_v5: 2 vCPU / 8 GB RAM — sufficient for ~200 concurrent users per node
    name: 'Standard_D2s_v5'
    tier: 'Standard'
    capacity: 2
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    orchestrationMode: 'Uniform'
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: take(replace('${prefix}web', '-', ''), 15)
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          provisionVMAgent: true
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-datacenter-azure-edition'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${prefix}-vmssnic'
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    primary: true
                    subnet: {
                      id: frontendSubnetId
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: loadBalancerBackendPoolId
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

resource vmssExtension 'Microsoft.Compute/virtualMachineScaleSets/extensions@2024-03-01' = {
  parent: vmss
  name: 'setupmoodlenode'
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: vmssCommand
    }
  }
}

resource autoscale 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: '${prefix}-vmss-autoscale'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'defaultProfile'
        capacity: {
          minimum: '2'
          maximum: '4'
          default: '2'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 35
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

resource controllerNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: controllerNicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: controlSubnetId
          }
        }
      }
    ]
  }
}

resource controllerVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: controllerVmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: take(replace('${prefix}controller', '-', ''), 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: controllerNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource controllerExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: controllerVm
  name: 'setupcontroller'
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: controllerCommand
    }
  }
}

output privateLinkServiceId string = privateLinkService.id
output loadBalancerPrivateIp string = loadBalancerPrivateIp
output vmssName string = vmss.name
output vmssPrincipalId string = vmss.identity.principalId
output controllerVmName string = controllerVm.name
output controllerPrincipalId string = controllerVm.identity.principalId
