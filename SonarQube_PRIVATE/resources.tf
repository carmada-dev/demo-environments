data "azuread_client_config" "Current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "MSGraph" {
  application_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
} 

data "azurerm_resource_group" "Environment" {
  name = "${var.resource_group_name}"
}

data "azurerm_app_configuration_key" "Settings_PrivateLinkResourceGroupId" {
  configuration_store_id = data.azurerm_resource_group.Environment.tags["hidden-ConfigurationStoreId"]
  key                    = "PrivateLinkDnsZoneRG"
#   label                  = data.azurerm_resource_group.Environment.tags["EnvironmentType"]
}

data "azurerm_app_configuration_key" "Settings_ProjectNetworkId" {
  configuration_store_id = data.azurerm_resource_group.Environment.tags["hidden-ConfigurationStoreId"]
  key                    = "ProjectNetworkId"
#   label                  = data.azurerm_resource_group.Environment.tags["EnvironmentType"]
}

data "azurerm_app_configuration_key" "Settings_EnvironmentNetworkId" {
  configuration_store_id = data.azurerm_resource_group.Environment.tags["hidden-ConfigurationStoreId"]
  key                    = "EnvironmentNetworkId"
  label                  = data.azurerm_resource_group.Environment.tags["EnvironmentType"]
}

data "external" "DNSZoneDatabase" {
	program = [ "bash", "-c", "${path.module}/scripts/EnsurePrivateDnsZone.sh"]
	query = {
	  RESOURCEGROUPID = "${data.azurerm_app_configuration_key.Settings_PrivateLinkResourceGroupId.value}"
	  PROJECTNETWORKID = "${data.azurerm_app_configuration_key.Settings_ProjectNetworkId.value}"
	  ENVIRONMENTNETWORKID = "${data.azurerm_app_configuration_key.Settings_EnvironmentNetworkId.value}"
	  DNSZONENAME = "privatelink.database.windows.net"
	}
}

data "external" "DNSZoneApplication" {
	program = [ "bash", "-c", "${path.module}/scripts/EnsurePrivateDnsZone.sh"]
	query = {
	  RESOURCEGROUPID = "${data.azurerm_app_configuration_key.Settings_PrivateLinkResourceGroupId.value}"
	  PROJECTNETWORKID = "${data.azurerm_app_configuration_key.Settings_ProjectNetworkId.value}"
	  ENVIRONMENTNETWORKID = "${data.azurerm_app_configuration_key.Settings_EnvironmentNetworkId.value}"
	  DNSZONENAME = "privatelink.azurewebsites.net"
	}
}

data "external" "DNSZoneApplicationSCM" {
	program = [ "bash", "${path.module}/scripts/EnsurePrivateDnsZone.sh"]
	query = {
	  RESOURCEGROUPID = "${data.azurerm_app_configuration_key.Settings_PrivateLinkResourceGroupId.value}"
	  PROJECTNETWORKID = "${data.azurerm_app_configuration_key.Settings_ProjectNetworkId.value}"
	  ENVIRONMENTNETWORKID = "${data.azurerm_app_configuration_key.Settings_EnvironmentNetworkId.value}"
	  DNSZONENAME = "scm.privatelink.azurewebsites.net"
	}
}

resource "random_integer" "ResourceSuffix" {
	min 					= 10000
	max						= 99999
}

resource "random_password" "DatabasePassword" {
	length					= 20
	min_lower 				= 5
	min_upper 				= 5
	min_numeric 			= 5
	min_special 			= 5
}

resource "azurerm_service_plan" "SonarQube" {
	name                	= "sonarqube${random_integer.ResourceSuffix.result}-srv"
	location            	= data.azurerm_resource_group.Environment.location
	resource_group_name 	= data.azurerm_resource_group.Environment.name

	os_type             	= "Linux"
	sku_name            	= "P1v2"
}

resource "azurerm_linux_web_app" "SonarQube" {
	name                	= "sonarqube${random_integer.ResourceSuffix.result}-web"
	location            	= data.azurerm_resource_group.Environment.location
	resource_group_name 	= data.azurerm_resource_group.Environment.name
	
	service_plan_id 		= azurerm_service_plan.SonarQube.id
	https_only 				= true

	app_settings 			= {
		"SONAR_JDBC_URL": "jdbc:sqlserver://${azurerm_mssql_server.SonarQube.fully_qualified_domain_name};databaseName=${azurerm_mssql_database.SonarQube.name};encrypt=true;trustServerCertificate=false;hostNameInCertificate=${replace(azurerm_mssql_server.SonarQube.fully_qualified_domain_name, "${azurerm_mssql_server.SonarQube.name}.", "*.")};loginTimeout=30;"
		"SONAR_JDBC_USERNAME": "SonarQube"
		"SONAR_JDBC_PASSWORD": "${random_password.DatabasePassword.result}"
		"SONAR_SEARCH_JAVAADDITIONALOPTS": "-Dnode.store.allow_mmap=false"
		"sonar.path.data": "/home/sonarqube/data"
	}

	logs {
		http_logs {
		  file_system {
			retention_in_days = 7
			retention_in_mb = 35
		  }
		}
	}

	site_config {
	   	always_on 		= "true"

		application_stack {
			docker_image 		= "sonarqube"
			docker_image_tag  	= "lts-community"
		}
	}
}

resource "azurerm_mssql_server" "SonarQube" {
	name							= "sonarqube${random_integer.ResourceSuffix.result}-sql"
	location            			= data.azurerm_resource_group.Environment.location
	resource_group_name 			= data.azurerm_resource_group.Environment.name

	version                      	= "12.0"
	administrator_login          	= "SonarQube"
	administrator_login_password 	= "${ random_password.DatabasePassword.result }"
	public_network_access_enabled 	= false
}

resource "azurerm_mssql_database" "SonarQube" {
	name           					= "sonar"
	server_id      					= azurerm_mssql_server.SonarQube.id

	sku_name       					= "GP_S_Gen5_2"
	collation      					= "SQL_Latin1_General_CP1_CS_AS"
	min_capacity 					= 1
	max_size_gb 					= 16
	auto_pause_delay_in_minutes 	= 60
}

resource "azurerm_private_endpoint" "SonarQubePL_Database" {
	name 							= "${azurerm_mssql_server.SonarQube.name}"
	location            			= data.azurerm_resource_group.Environment.location
	resource_group_name 			= data.azurerm_resource_group.Environment.name

	subnet_id 						= "${data.azurerm_app_configuration_key.Settings_EnvironmentNetworkId.value}/subnets/default"

	private_service_connection {
		name = "default"
		is_manual_connection = "false"
		private_connection_resource_id = azurerm_mssql_server.SonarQube.id
		subresource_names = ["sqlServer"]
	}

	private_dns_zone_group {
		name                 = "default"
		private_dns_zone_ids = [ data.external.DNSZoneDatabase.result.DNSZONEID ]
  	}
}

resource "azurerm_private_endpoint" "SonarQubePL_Application" {
	name 							= "${azurerm_linux_web_app.SonarQube.name}"
	location            			= data.azurerm_resource_group.Environment.location
	resource_group_name 			= data.azurerm_resource_group.Environment.name

	subnet_id 						= "${data.azurerm_app_configuration_key.Settings_EnvironmentNetworkId.value}/subnets/default"

	private_service_connection {
		name = "default"
		is_manual_connection = "false"
		private_connection_resource_id = azurerm_linux_web_app.SonarQube.id
		subresource_names = ["sites"]
	}

	private_dns_zone_group {
		name                 = "default"
		private_dns_zone_ids = [ data.external.DNSZoneApplication.result.DNSZONEID, data.external.DNSZoneApplicationSCM.result.DNSZONEID ]
  	}
}

resource "azuread_application" "SonarQube" {
	display_name 					= "${data.azurerm_resource_group.Environment.name}-${azurerm_linux_web_app.SonarQube.default_hostname}"
	identifier_uris  				= [ "api://${data.azurerm_resource_group.Environment.name}-${azurerm_linux_web_app.SonarQube.default_hostname}" ]
	owners 							= [ data.azuread_client_config.Current.object_id ]
	sign_in_audience 				= "AzureADMyOrg"

	web {
		homepage_url  = "https://${azurerm_linux_web_app.SonarQube.default_hostname}"
		redirect_uris = ["https://${azurerm_linux_web_app.SonarQube.default_hostname}/oauth2/callback/aad"]
	}
	
	required_resource_access {
		resource_app_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph

		resource_access {
			id   = data.azuread_service_principal.MSGraph.oauth2_permission_scope_ids["User.Read"]
			type = "Scope"
		}

		resource_access {
			id   = data.azuread_service_principal.MSGraph.oauth2_permission_scope_ids["User.ReadBasic.All"]
			type = "Scope"
		}
	}
}

resource "azuread_service_principal" "SonarQube" {
  application_id = azuread_application.SonarQube.application_id
}

resource "azuread_service_principal_password" "SonarQube" {
  service_principal_id = azuread_service_principal.SonarQube.id
  end_date_relative = "87660h" # 10 years
}

resource "null_resource" "SonarQubeInit" {

	provisioner "local-exec" {
		interpreter = [ "/bin/bash", "-c" ]
		command = "${path.module}/scripts/InitSonarQube.sh"
		environment = {
		  HOSTNAME = azurerm_linux_web_app.SonarQube.default_hostname
		  PASSWORD =  var.sonarqube_admin_password
		  CLIENTID = azuread_application.SonarQube.application_id
		  CLIENTSECRET = azuread_service_principal_password.SonarQube.value
		}
	}

	depends_on = [ 
		azurerm_mssql_database.SonarQube,
		azurerm_linux_web_app.SonarQube
	]
}
