targetScope = 'resourceGroup'

// ============================================================================================

// ============================================================================================

#disable-next-line no-loc-expr-outside-params
var ResourceLocation = resourceGroup().location
var ResourcePrefix = uniqueString(resourceGroup().id)

var SqlServerAdminUsername = 'Sonarqube'
var SqlServerAdminPassword = guid(deployment().name, resourceGroup().id)

var SonarqubeImageVersion = 'lts-community'
var SonarqubeDatabaseName = 'Sonarqube'

var EnvironmentNetworkIdSegments = split(resourceGroup().tags.EnvironmentNetworkId, '/')

// ============================================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' existing = {
  name: last(EnvironmentNetworkIdSegments)
  scope: resourceGroup(EnvironmentNetworkIdSegments[2], EnvironmentNetworkIdSegments[4])
}

resource defaultSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = {
  name : 'default'
  parent: virtualNetwork
}

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: '${ResourcePrefix}-SQL'
  location: ResourceLocation
  properties: {
    administratorLogin: SqlServerAdminUsername
    administratorLoginPassword: SqlServerAdminPassword
    version: '12.0'
  }
}

resource sqlFirewall 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview'= {
  name: '${ResourcePrefix}-SQL-FW'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  name: SonarqubeDatabaseName
  location: ResourceLocation
  parent: sqlServer
  sku: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CS_AS'
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 17179869184
  }
}

resource webServer 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${ResourcePrefix}-SRV'
  location: ResourceLocation
  kind: 'linux'
  sku: {
    name: 'S2'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    targetWorkerSizeId: 1
    targetWorkerCount: 1
    reserved: true
  }
}

resource webSite 'Microsoft.Web/sites@2022-03-01' = {
  name: '${ResourcePrefix}-APP'
  location: ResourceLocation
  properties: {
    serverFarmId: webServer.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|sonarqube:${SonarqubeImageVersion}'
    }
  }
}

resource webSiteConfig 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'appsettings'
  parent: webSite
  properties: {
    SONARQUBE_JDBC_URL: 'jdbc:sqlserver://${sqlServer.properties.fullyQualifiedDomainName};databaseName=${sqlDatabase.name};encrypt=true;trustServerCertificate=false;hostNameInCertificate=${replace(sqlServer.properties.fullyQualifiedDomainName, '${sqlServer.name}.', '.*')};loginTimeout=30;'
    SONARQUBE_JDBC_USERNAME: SqlServerAdminUsername
    SONARQUBE_JDBC_PASSWORD: SqlServerAdminPassword
    'sonar.path.data': '/home/sonarqube/data'
  }
}
