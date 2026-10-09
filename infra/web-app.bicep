@description('The App Service name. Must be globally unique.')
param name string

param location string = resourceGroup().location

@description('The sign-in method this app serves.')
@allowed([
  'oidc'
  'saml'
])
param authProvider string

@description('The existing App Service plan this app runs on.')
param appServicePlanName string

@description('The existing virtual network used for regional VNet integration.')
param virtualNetworkName string

@description('The existing subnet delegated to Microsoft.Web/serverFarms.')
param integrationSubnetName string = 'app-service-integration'

@description('The existing Storage account this app reads and writes.')
param storageAccountName string

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' existing = {
  name: appServicePlanName
}

resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  name: '${virtualNetworkName}/${integrationSubnetName}'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// App settings are intentionally not declared here: an ARM deployment replaces
// all settings, which would erase the identity-provider values set after deployment.
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: name
  location: location
  tags: {
    authProvider: authProvider
  }
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    virtualNetworkSubnetId: integrationSubnet.id
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      vnetRouteAllEnabled: true
    }
  }
}

resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output name string = webApp.name
output url string = 'https://${webApp.properties.defaultHostName}'