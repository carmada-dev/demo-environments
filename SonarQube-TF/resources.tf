resource "null_resource" "Environment" {

	triggers = {
		always_run = "${timestamp()}"
	}

	provisioner "local-exec" {
		interpreter = [ "/bin/bash", "-c" ]
		command  = "mkdir -p '${path.module}/.temp' && az group show --resource-group ${var.resource_group_name} > '${path.module}/.temp/environment.json'"
	}
}

data "local_file" "Environment" {
	filename = "${path.module}/.temp/environment.json"
  	depends_on = [ null_resource.Environment ]
}

locals {
	environment = jsondecode(data.local_file.Environment.content)
}

resource "random_integer" "ResourceSuffix" {
	min 					= 10000
	max						= 99999
}

resource "random_password" "DatabasePassword" {
	length					= 16
	special					= false
}

resource "azurerm_service_plan" "SonarQube" {
	name                	= "sonarqube${random_integer.ResourceSuffix.result}"
	location            	= local.environment.location
	resource_group_name 	= local.environment.name

	os_type             	= "Linux"
	sku_name            	= "P1v2"
}

resource "azurerm_linux_web_app" "SonarQube" {
	name                	= "sonarqube${random_integer.ResourceSuffix.result}"
	location            	= local.environment.location
	resource_group_name 	= local.environment.name
	
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
	name							= "sonarqube${random_integer.ResourceSuffix.result}"
	location            			= local.environment.location
	resource_group_name 			= local.environment.name

	version                      	= "12.0"
	administrator_login          	= "SonarQube"
	administrator_login_password 	= "${ random_password.DatabasePassword.result }"
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

resource "azurerm_mssql_firewall_rule" "SonarQube" {
   name             				= "FirewallRule"
   server_id        				= azurerm_mssql_server.SonarQube.id
   start_ip_address 				= "0.0.0.0"
   end_ip_address   				= "0.0.0.0"
}

resource "null_resource" "SonarQubeInit" {

	triggers = {
		shell_hash = "${filesha256("${path.module}/scripts/InitSonarQube.sh")}"
	}

	provisioner "local-exec" {
		interpreter = [ "/bin/bash", "-c" ]
		command  = "${path.module}/scripts/InitSonarQube.sh -h ${azurerm_linux_web_app.SonarQube.default_hostname} -p ${var.sonarqube_admin_password}"
	}

	depends_on = [ 
		azurerm_mssql_database.SonarQube,
		azurerm_mssql_firewall_rule.SonarQube 
	]
}
