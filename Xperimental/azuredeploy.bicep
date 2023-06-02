targetScope = 'resourceGroup'

// ============================================================================================

module EnvironmentSettings '../_shared/EnvironmentSettings.bicep' = {
  name: '${take(deployment().name, 36)}_${uniqueString('EnvironmentSettings')}'
}

// ============================================================================================
