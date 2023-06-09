param image string = 'mcr.microsoft.com/appsvc/staticsite:latest'

#disable-next-line no-loc-expr-outside-params
var resourceLocation = resourceGroup().location
var resourcePrefix = uniqueString(resourceGroup().id)

// ============================================================================================

resource webServer 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${resourcePrefix}-SRV'
  location: resourceLocation
  kind: 'linux'
  properties: {
    reserved: true
  }	
  sku:  {
  	name: 'B1'
    tier: 'Basic'
  }
}

resource webSite 'Microsoft.Web/sites@2022-03-01' = {
  name: '${resourcePrefix}-APP'
  location: resourceLocation
  properties: {
    serverFarmId: webServer.id
    siteConfig: {
      appSettings: []
      linuxFxVersion: 'DOCKER|${image}'
    }
  }
}

