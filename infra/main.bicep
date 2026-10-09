@description('The name of the environment. Shared resources and both web apps are named from it.')
param environmentName string = 'mcawebpolicy'

@description('The Azure region for deployment.')
param location string = resourceGroup().location

@description('The SKU for the App Service plan. VNet integration and Always On require Basic (B1) or higher.')
param appServicePlanSku string = 'B1'

@description('The Azure Storage account name.')
param storageAccountName string

@description('The container used by the OIDC web app.')
param storageContainerName string = 'mdca-files'

@description('The container used by the SAML web app.')
param samlStorageContainerName string = 'mdca-files-saml'

@description('The address space for the application virtual network.')
param virtualNetworkAddressPrefix string = '10.20.0.0/16'

@description('The address prefix for the App Service integration subnet. A /26 or larger subnet is recommended.')
param appServiceIntegrationSubnetAddressPrefix string = '10.20.0.0/26'

@description('The address prefix for the Storage private endpoint subnet.')
param privateEndpointSubnetAddressPrefix string = '10.20.0.64/27'

var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${environmentName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'app-service-integration'
        properties: {
          addressPrefix: appServiceIntegrationSubnetAddressPrefix
          delegations: [
            {
              name: 'app-service-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource appServiceIntegrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: virtualNetwork
  name: 'app-service-integration'
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: virtualNetwork
  name: 'private-endpoints'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource storageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: storageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource samlStorageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: samlStorageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: blobPrivateDnsZoneName
  location: 'global'
}

resource blobPrivateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobPrivateDnsZone
  name: '${environmentName}-blob-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${environmentName}-storage-blob-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${environmentName}-storage-blob-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource storageBlobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${environmentName}-plan'
  location: location
  sku: {
    name: appServicePlanSku
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Web apps are deployed separately by infra/web-app.bicep, once per sign-in method.
output appServicePlanName string = appServicePlan.name
output virtualNetworkName string = virtualNetwork.name
output integrationSubnetName string = appServiceIntegrationSubnet.name
output storageAccountName string = storageAccount.name
output storageContainerName string = storageContainerName
output samlStorageContainerName string = samlStorageContainerName