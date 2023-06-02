targetScope = 'resourceGroup'

// ============================================================================================

resource settings 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'EnvironmentSettings'
  #disable-next-line no-loc-expr-outside-params
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceGroup().tags.EnvironmentDeployerId}': {}
    }
  }
  properties: {
    forceUpdateTag: guid(resourceGroup().id)
    azCliVersion: '2.42.0'
    timeout: 'PT30M'
    environmentVariables: [
      {
        name: 'ConfigurationStore'
        value: resourceGroup().tags.ProjectConfigurationUrl
      }
      {
        name: 'EnvironmentType'
        value: resourceGroup().tags.EnvironmentTypeName
      }
    ]
    scriptContent: loadTextContent('EnvironmentSettings.sh') 
    cleanupPreference: 'Always'
    retentionInterval: 'P1D'
  }
}

// ============================================================================================

output Settings object = settings.properties.outputs
