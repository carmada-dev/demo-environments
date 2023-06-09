
variable "resource_group_name" {
	type 		= string
	nullable 	= false
}

variable "sonarqube_admin_password" {
	type 		= string
	sensitive 	= true
}

