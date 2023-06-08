terraform {
	required_providers {
		azurerm = {
			source  = "hashicorp/azurerm"
			version = ">=3.0.0"
		}
	}
}

provider "azurerm" {
	features {}
	subscription_id = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
	# skip_provider_registration = true
}

variable "SonarQubeAdminPassword" {
	type = string
	default = "T00ManySecrets"
}

variable "SQLUsername" {
	type = string
	default = "godfather"
}

variable "SQLPassword" {
	type = string
	default = "T00ManySecrets"
}

resource "random_integer" "unique" {
	min = 10000
	max = 99999
}

resource "azurerm_resource_group" "SonarQube" {
	name     = "SonarQube"
	location = "West Europe"
}

resource "azurerm_service_plan" "SonarQube" {
	name                = "sonarqube${random_integer.unique.result}"
	location            = azurerm_resource_group.SonarQube.location
	resource_group_name = azurerm_resource_group.SonarQube.name

	os_type             = "Linux"
	sku_name            = "P1v2"
}

resource "azurerm_linux_web_app" "SonarQube" {
	name                = "sonarqube${random_integer.unique.result}"
	location            = azurerm_resource_group.SonarQube.location
	resource_group_name = azurerm_resource_group.SonarQube.name
	
	service_plan_id 	= azurerm_service_plan.SonarQube.id
	https_only 			= true

	app_settings 		= {
		"SONAR_JDBC_URL": "jdbc:sqlserver://${azurerm_mssql_server.SonarQube.fully_qualified_domain_name};databaseName=${azurerm_mssql_database.SonarQube.name};encrypt=true;trustServerCertificate=false;hostNameInCertificate=${replace(azurerm_mssql_server.SonarQube.fully_qualified_domain_name, "${azurerm_mssql_server.SonarQube.name}.", "*.")};loginTimeout=30;"
		"SONAR_JDBC_USERNAME": "${var.SQLUsername}"
		"SONAR_JDBC_PASSWORD": "${var.SQLPassword}"
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
	name                         = "sonarqube${random_integer.unique.result}"
	resource_group_name          = azurerm_resource_group.SonarQube.name
	location                     = azurerm_resource_group.SonarQube.location

	version                      = "12.0"
	administrator_login          = "godfather"
	administrator_login_password = "T00ManySecrets"
}

resource "azurerm_mssql_database" "SonarQube" {
	name           	= "sonar"
	server_id      	= azurerm_mssql_server.SonarQube.id

	sku_name       				= "GP_S_Gen5_2"
	collation      				= "SQL_Latin1_General_CP1_CS_AS"
	min_capacity 				= 1
	max_size_gb 				= 16
	auto_pause_delay_in_minutes = 60
}

resource "azurerm_mssql_firewall_rule" "SonarQube" {
   name             = "FirewallRule"
   server_id        = azurerm_mssql_server.SonarQube.id
   start_ip_address = "0.0.0.0"
   end_ip_address   = "0.0.0.0"
}

# resource "azurerm_mssql_firewall_rule" "SonarQube" {
#    for_each         = toset(azurerm_linux_web_app.SonarQube.outbound_ip_address_list)
#    name             = "FirewallRule"
#    server_id        = azurerm_mssql_server.SonarQube.id
#    start_ip_address = each.key
#    end_ip_address   = each.key
# }

resource "null_resource" "SonarQubeInit" {

	triggers = {
		shell_hash = "${filesha256("${path.module}/scripts/InitSonarQube.sh")}"
	}

	provisioner "local-exec" {
		interpreter = [ "/bin/bash", "-c" ]
		command  = "${path.module}/scripts/InitSonarQube.sh -h ${azurerm_linux_web_app.SonarQube.default_hostname} -p ${var.SonarQubeAdminPassword}"
	}

	depends_on = [ 
		azurerm_mssql_database.SonarQube,
		azurerm_mssql_firewall_rule.SonarQube 
	]
}
