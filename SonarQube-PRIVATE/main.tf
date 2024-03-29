data "azuread_client_config" "Current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "MSGraph" {
  application_id 				= data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
} 

module "ade_context" {
	source 						= "git::https://git@github.com/carmada-dev/terraform.git//ade_context?ref=main"
	resourceGroup 				= var.resource_group_name
}

module "ade_allocateIpRange" {
	source 						= "git::https://git@github.com/carmada-dev/terraform.git//ade_allocateIpRange?ref=main"
	resourceGroup 				= var.resource_group_name
	cidrBlocks 					= [ 25, 25 ]
}

resource "azurerm_route_table" "SonarQube" {
  	name                    	= "sonarqube-${module.ade_context.Environment.Suffix}-route"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name

	route {
		name           			= "default"
		address_prefix 			= "0.0.0.0/0"
		next_hop_type  			= "VirtualAppliance"
		next_hop_in_ip_address 	= module.ade_context.Settings["ProjectGatewayIP"]
	}
}

resource "azurerm_virtual_network" "SonarQube" {
	name                		= "sonarqube-${module.ade_context.Environment.Suffix}-net"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name

	depends_on 					= [ module.ade_allocateIpRange ]

	address_space       		= module.ade_allocateIpRange.IPRanges
	dns_servers         		= ["168.63.129.16", module.ade_context.Settings["ProjectGatewayIP"]]
}

resource "azurerm_subnet" "SonarQube_Default" {
	name                 		= "default"
	resource_group_name 		= module.ade_context.Environment.Name

	depends_on 					= [ module.ade_allocateIpRange ]

	virtual_network_name		= azurerm_virtual_network.SonarQube.name
	address_prefixes     		= [ module.ade_allocateIpRange.IPRanges[0] ]
}

resource "azurerm_subnet_route_table_association" "SonarQube_Default_Routes" {
  subnet_id      				= azurerm_subnet.SonarQube_Default.id
  route_table_id 				= azurerm_route_table.SonarQube.id
}

resource "azurerm_subnet" "SonarQube_WebServer" {
	name                 		= "webserver"
	resource_group_name 		= module.ade_context.Environment.Name

	depends_on 					= [ module.ade_allocateIpRange ]

	virtual_network_name 		= azurerm_virtual_network.SonarQube.name
	address_prefixes     		= [ module.ade_allocateIpRange.IPRanges[1] ]

	delegation {
		name 					= "Microsoft.Web/serverFarms"
		service_delegation {
			name    			= "Microsoft.Web/serverFarms"
		}
	}
}

resource "azurerm_subnet_route_table_association" "SonarQube_WebServer_Routes" {
  subnet_id      				= azurerm_subnet.SonarQube_WebServer.id
  route_table_id 				= azurerm_route_table.SonarQube.id
}

module "ade_peerNetwork" {
	source 						= "git::https://git@github.com/carmada-dev/terraform.git//ade_peerNetwork?ref=main"
	resourceGroup 				= var.resource_group_name
	networkName					= azurerm_virtual_network.SonarQube.name
}

module "ade_linkDnsZone_database" {
	source 						= "git::https://git@github.com/carmada-dev/terraform.git//ade_linkDnsZone?ref=main"
	resourceGroup 				= var.resource_group_name
	networkName					= azurerm_virtual_network.SonarQube.name
	dnsZoneName					= "privatelink.database.windows.net"
}

module "ade_linkDnsZone_website" {
	source 						= "git::https://git@github.com/carmada-dev/terraform.git//ade_linkDnsZone?ref=main"
	resourceGroup 				= var.resource_group_name
	networkName					= azurerm_virtual_network.SonarQube.name
	dnsZoneName					= "privatelink.azurewebsites.net"
}

module "ade_linkDnsZone_websiteSCM" {
	source 						= "git::https://git@github.com/carmada-dev/terraform.git//ade_linkDnsZone?ref=main"
	resourceGroup 				= var.resource_group_name
	networkName					= azurerm_virtual_network.SonarQube.name
	dnsZoneName					= "scm.privatelink.azurewebsites.net"
}

resource "random_password" "DatabasePassword" {
	length						= 20
	min_lower 					= 5
	min_upper 					= 5
	min_numeric 				= 5
	min_special 				= 5
}


resource "azurerm_service_plan" "SonarQube" {
	name                		= "sonarqube-${module.ade_context.Environment.Suffix}-srv"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name

	os_type             		= "Linux"
	sku_name            		= "P1v2"
}

resource "azurerm_linux_web_app" "SonarQube" {
	name                		= "sonarqube-${module.ade_context.Environment.Suffix}-web"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name
	
	service_plan_id 			= azurerm_service_plan.SonarQube.id
	https_only 					= true

	app_settings = {
		"SONAR_JDBC_URL": "jdbc:sqlserver://${azurerm_mssql_server.SonarQube.fully_qualified_domain_name};databaseName=${azurerm_mssql_database.SonarQube.name};encrypt=true;trustServerCertificate=false;hostNameInCertificate=${replace(azurerm_mssql_server.SonarQube.fully_qualified_domain_name, "${azurerm_mssql_server.SonarQube.name}.", "*.")};loginTimeout=30;"
		"SONAR_JDBC_USERNAME": "SonarQube"
		"SONAR_JDBC_PASSWORD": "${random_password.DatabasePassword.result}"
		"SONAR_SEARCH_JAVAADDITIONALOPTS": "-Dnode.store.allow_mmap=false"
		"sonar.path.data": "/home/sonarqube/data"
	}

	logs {
		http_logs {
		  file_system {
			retention_in_days 	= 7
			retention_in_mb 	= 35
		  }
		}
	}

	site_config {
	   	always_on 				= "true"
		
		application_stack {
			docker_image 		= "sonarqube"
			docker_image_tag  	= "lts-community"
		}
	}
}

resource "azurerm_app_service_virtual_network_swift_connection" "SonarQube" {
	app_service_id 				= azurerm_linux_web_app.SonarQube.id
	subnet_id      				= azurerm_subnet.SonarQube_WebServer.id
}

resource "azurerm_mssql_server" "SonarQube" {
	name						= "sonarqube-${module.ade_context.Environment.Suffix}-sql"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name

	version                      	= "12.0"
	administrator_login          	= "SonarQube"
	administrator_login_password 	= "${ random_password.DatabasePassword.result }"
	public_network_access_enabled 	= false
}

resource "azurerm_mssql_database" "SonarQube" {
	name           				= "sonar"
	server_id      				= azurerm_mssql_server.SonarQube.id

	sku_name       				= "GP_S_Gen5_2"
	collation      				= "SQL_Latin1_General_CP1_CS_AS"
	min_capacity 				= 1
	max_size_gb 				= 16
	auto_pause_delay_in_minutes = 60
}

resource "azuread_application" "SonarQube" {
	display_name 				= "${module.ade_context.Environment.Name}-${azurerm_linux_web_app.SonarQube.default_hostname}"
	identifier_uris  			= [ "api://${module.ade_context.Environment.Name}-${azurerm_linux_web_app.SonarQube.default_hostname}" ]
	# owners 							= [ data.azuread_client_config.Current.object_id ]
	sign_in_audience 			= "AzureADMyOrg"

	web {
		homepage_url  			= "https://${azurerm_linux_web_app.SonarQube.default_hostname}"
		redirect_uris 			= [ "https://${azurerm_linux_web_app.SonarQube.default_hostname}/oauth2/callback/aad" ]
	}
	
	required_resource_access {
		resource_app_id 		= data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph

		resource_access {
			id   				= data.azuread_service_principal.MSGraph.oauth2_permission_scope_ids["User.Read"]
			type 				= "Scope"
		}

		resource_access {
			id   				= data.azuread_service_principal.MSGraph.oauth2_permission_scope_ids["User.ReadBasic.All"]
			type 				= "Scope"
		}
	}
}

resource "azuread_service_principal" "SonarQube" {
  application_id 				= azuread_application.SonarQube.application_id
}

resource "azuread_service_principal_password" "SonarQube" {
  service_principal_id 			= azuread_service_principal.SonarQube.id
  end_date_relative 			= "87660h" # 10 years
}

resource "null_resource" "SonarQubeInit" {

	provisioner "local-exec" {
		interpreter 			= [ "/bin/bash" ]
		command 				= "${path.module}/scripts/InitSonarQube.sh"
		environment = {
		  HOSTNAME 				= azurerm_linux_web_app.SonarQube.default_hostname
		  PASSWORD 				= var.sonarqube_admin_password
		  CLIENTID 				= azuread_application.SonarQube.application_id
		  CLIENTSECRET 			= azuread_service_principal_password.SonarQube.value
		}
	}

	depends_on = [ 
		# database needs to be hooked up with a private endpoint
		azurerm_private_endpoint.SonarQubePL_Database,
		# the app service need a outgoing network connection enabling to talk to the db private endpoint
		azurerm_app_service_virtual_network_swift_connection.SonarQube
	]
}

resource "azurerm_private_endpoint" "SonarQubePL_Database" {
	name 						= "${azurerm_mssql_server.SonarQube.name}"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name

	subnet_id 					= azurerm_subnet.SonarQube_Default.id

	private_service_connection {
		name 							= "default"
		is_manual_connection 			= "false"
		private_connection_resource_id 	= azurerm_mssql_server.SonarQube.id
		subresource_names 				= [ "sqlServer" ]
	}

	private_dns_zone_group {
		name                 	= "default"
		private_dns_zone_ids 	= [ module.ade_linkDnsZone_database.DnsZoneId ]
  	}
}

resource "azurerm_private_endpoint" "SonarQubePL_Application" {
	name 						= "${azurerm_linux_web_app.SonarQube.name}"
	location            		= module.ade_context.Environment.Location
	resource_group_name 		= module.ade_context.Environment.Name

	subnet_id 					= azurerm_subnet.SonarQube_Default.id

	private_service_connection {
		name 							= "default"
		is_manual_connection 			= "false"
		private_connection_resource_id 	= azurerm_linux_web_app.SonarQube.id
		subresource_names 				= [ "sites" ]
	}

	private_dns_zone_group {
		name                 	= "default"
		private_dns_zone_ids 	= [ 
			module.ade_linkDnsZone_website.DnsZoneId,
			module.ade_linkDnsZone_websiteSCM.DnsZoneId
		]
  	}

	depends_on = [ 
		# we need to wait until sq is initialized 
		# before we hide it behind a private endpoint
		null_resource.SonarQubeInit 
	]
}

