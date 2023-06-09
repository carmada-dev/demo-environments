data "azurerm_resource_group" "ResourceGroup" {
  name = var.resource_group_name
}

resource "random_integer" "ResourceSuffix" {
	min 					= 10000
	max						= 99999
}

resource "azurerm_storage_account" "example" {
  name                     = "hipster${ resource.random_integer.ResourceSuffix.result}"
  resource_group_name      = data.azurerm_resource_group.ResourceGroup.name
  location                 = data.azurerm_resource_group.ResourceGroup.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}