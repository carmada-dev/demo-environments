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
	resource_group = jsondecode(data.local_file.Environment.content)
}

resource "random_integer" "ResourceSuffix" {
	min 					= 10000
	max						= 99999
}

resource "random_password" "DatabasePassword" {
	length					= 16
	special					= false
}

resource "azurerm_storage_account" "example" {
  name                     = "hipster${ resource.random_integer.ResourceSuffix.result}"
  resource_group_name      = local.resource_group.name
  location                 = local.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}