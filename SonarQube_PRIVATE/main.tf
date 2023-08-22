terraform {
	required_providers {
		azurerm = {
			version = "=3.59.0"
		}
		azuread = {
			
		}
		random = {

		}
	}
}

provider "azurerm" {
	features {}
	skip_provider_registration = true
}