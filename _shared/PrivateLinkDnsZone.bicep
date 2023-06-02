targetScope = 'resourceGroup'

// ============================================================================================

param DNSZoneName string

// ============================================================================================

module EnvironmentSettings 'EnvironmentSettings.bicep' = {
  name: '${take(deployment().name, 36)}_${uniqueString(deployment().name)}'
}

resource PrivateLinkDnsZone 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'PrivateLinkDnsZone-${replace(DNSZoneName, '.', '_')}'
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
    forceUpdateTag: guid(DNSZoneName)
    azCliVersion: '2.40.0'
    timeout: 'PT30M'
    environmentVariables: [
      {
        name: 'Subscription'
        value: split(EnvironmentSettings.outputs.Settings.PrivateLinkResourceGroupId, '/')[2]
      }
      {
        name: 'ResourceGroup'
        value: split(EnvironmentSettings.outputs.Settings.PrivateLinkResourceGroupId, '/')[4]
      }
      {
        name: 'DNSZoneName'
        value: DNSZoneName
      }
    ]
    scriptContent: loadTextContent('PrivateLinkDnsZone.sh') 
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

// ============================================================================================

output DNSZoneId string = PrivateLinkDnsZone.properties.outputs.DNSZoneId
