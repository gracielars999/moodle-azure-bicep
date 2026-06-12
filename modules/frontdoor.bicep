@description('Prefix used for naming Front Door resources.')
param prefix string

@description('Location for Front Door resources. Use global for Azure Front Door.')
param location string = 'global'

@description('Tags applied to all taggable resources in this module.')
param tags object

@description('Custom domain to bind to Azure Front Door.')
param customDomain string

@description('Resource ID of the Private Link Service exposed behind the internal load balancer.')
param privateLinkResourceId string

@description('Origin host header and hostname used by Front Door to reach the internal load balancer.')
param originHostName string

@description('Azure region where the Private Link Service is deployed. Required by Front Door to approve the private endpoint connection.')
param privateLinkLocation string

var profileName = '${prefix}-afd-profile'
var endpointName = '${prefix}-afd-endpoint'
var originGroupName = '${prefix}-origin-group'
var originName = '${prefix}-origin'
var routeName = '${prefix}-route'
var customDomainResourceName = replace(replace(customDomain, '.', '-'), '*', 'wildcard')

resource profile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: profileName
  location: location
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: profile
  name: endpointName
  location: location
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: '${prefix}-afd-waf'
  location: location
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleSetAction: 'Block'
        }
      ]
    }
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: profile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      additionalLatencyInMilliseconds: 50
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probeIntervalInSeconds: 120
      probePath: '/login/index.php'
      probeProtocol: 'Http'
      probeRequestType: 'GET'
    }
    sessionAffinityState: 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: originName
  properties: {
    hostName: originHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: originHostName
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: false
    sharedPrivateLinkResource: {
      privateLink: {
        id: privateLinkResourceId
      }
      groupId: ''
      privateLinkLocation: privateLinkLocation
      requestMessage: 'Approve Azure Front Door Premium access to the Moodle private origin.'
    }
  }
}

resource customDomainResource 'Microsoft.Cdn/profiles/customDomains@2023-05-01' = {
  parent: profile
  name: customDomainResourceName
  properties: {
    hostName: customDomain
    tlsSettings: {
      certificateType: 'ManagedCertificate'
      minimumTlsVersion: 'TLS12'
    }
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: endpoint
  name: routeName
  properties: {
    customDomains: [
      {
        id: customDomainResource.id
      }
    ]
    originGroup: {
      id: originGroup.id
    }
    originPath: '/'
    patternsToMatch: [
      '/*'
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
    forwardingProtocol: 'MatchRequest'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: profile
  name: '${prefix}-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

output frontDoorEndpoint string = endpoint.properties.hostName
output profileName string = profile.name
