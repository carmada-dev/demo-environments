DEBUG="false"
CLEAN="false"
USERID="me"

while getopts 'o:p:e:t:u:dc' OPT; do
    case "$OPT" in
		o)
			ORGANIZATION="${OPTARG}" ;;
		p)
			PROJECT="${OPTARG}" ;;
		e)
			ENVIRONMENT="${OPTARG}" ;;
		t)
			ENVIRONMENTTYPE="${OPTARG}" ;;
		u)
			USERID="$(az ad user show --id ${OPTARG} --query id -o tsv | dos2unix)" ;;
		d)
			DEBUG="true" ;;
		c)
			CLEAN="true" ;;
    esac
done

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

deployEnvironment() {

	pushd "$(dirname "$1")" > /dev/null

	PARAMETERS="$([ -f './parameter.json' ] && (cat ./parameter.json | jq -c .) || echo '{}')"
	DEBUGARG="$([ "$DEBUG" == "true" ] && echo "--debug")"
	ENVIRONMENTNAME="$ENVIRONMENT-$(date +%s)"

	displayHeader "Resolve DevCenter and Project resource group ..."
	RESOURCEGROUP_DEVCENTER="$(az resource list --resource-type 'Microsoft.DevCenter/devcenters' --query "[?name=='$ORGANIZATION']|[0].resourceGroup" -o tsv)"
	[ -z "$RESOURCEGROUP_DEVCENTER" ] && >&2 echo "Unable to find resource group containing DevCenter '$ORGANIZATION'!" && exit 1 || echo "DevCenter RG:  $RESOURCEGROUP_DEVCENTER"
	RESOURCEGROUP_DEVPROJECT="$(az resource list --resource-type 'microsoft.devcenter/projects' --query "[?name=='$PROJECT']|[0].resourceGroup" -o tsv)"
	[ -z "$RESOURCEGROUP_DEVPROJECT" ] && >&2 echo "Unable to find resource group containing Project '$PROJECT'!" && exit 1 || echo "DevProject RG: $RESOURCEGROUP_DEVPROJECT"

	displayHeader "Synchronize DevCenter catalogs ..."
	while read CATALOGITEM; do
		echo "- $CATALOGITEM ..."
		az devcenter admin catalog sync --dev-center $ORGANIZATION --resource-group $RESOURCEGROUP_DEVCENTER --catalog-name $CATALOGITEM &
	done < <(az devcenter admin catalog list --dev-center $ORGANIZATION --resource-group $RESOURCEGROUP_DEVCENTER --query '[].name' -o tsv) && wait

	displayHeader "Ensure Azure AD permissions ..."

	AZURE_ROLES=()
	AZURE_ROLES+=('158c047a-c907-4556-b7ef-446551a6b5f7') # Application Administrator Role
	AZURE_ROLES+=('cf1c38e5-3621-4004-a7cb-879624dced7c') # Application Developer Role
	AZURE_ROLES+=('f2ef992c-3afb-46b9-b7cf-a126ee74c451') # Gloval Reader Role

	GRAPH_RESOURCEID=$(az ad sp list --query "[?appDisplayName=='Microsoft Graph'].id | [0]" --all -o tsv)

	GRAPH_ROLES=()	
	GRAPH_ROLES+=("$(az ad sp show --id $GRAPH_RESOURCEID --query "appRoles[?value=='Application.ReadWrite.OwnedBy'].id | [0]" -o tsv)")
	GRAPH_ROLES+=("$(az ad sp show --id $GRAPH_RESOURCEID --query "appRoles[?value=='Application.ReadWrite.All'].id | [0]" -o tsv)")

	for PRINCIPALID in $(az devcenter admin project-environment-type list --project-name $PROJECT --resource-group $RESOURCEGROUP_DEVPROJECT --query '[].identity.principalId' -o tsv | dos2unix); do
		echo "- Principal $PRINCIPALID"
		
		# for AZURE_ROLE in "${AZURE_ROLES[@]}"; do

		# 	echo "Azure role $AZURE_ROLE" && az rest \
		# 		--method post \
		# 		--uri https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments \
		# 		--headers "{ 'content-type': 'application/json' }" \
		# 		--body "{ '@odata.type': '#microsoft.graph.unifiedRoleAssignment', 'roleDefinitionId': '$AZURE_ROLE', 'principalId': '$PRINCIPALID', 'directoryScopeId': '/' }" \
		# 		--output none 2> /dev/null

		# done

		for GRAPH_ROLE in "${GRAPH_ROLES[@]}"; do

			echo "Graph role $GRAPH_ROLE" && az rest \
				--method post \
				--url "https://graph.microsoft.com/v1.0/servicePrincipals/$PRINCIPALID/appRoleAssignedTo" \
				--headers 'Content-Type=application/json' \
				--body "{ 'principalId': '$PRINCIPALID', 'resourceId': '$GRAPH_RESOURCEID', 'appRoleId': '$GRAPH_ROLE' }" \
				--output none 2> /dev/null &
		done
	done && wait && sleep 30

	displayHeader "Resolve catalog name ..."
	CATALOG="$(az devcenter dev environment-definition list --dev-center-name $ORGANIZATION --project-name $PROJECT --query "[?name=='$ENVIRONMENT']|[0].catalogName" -o tsv)"
	[ -z "$CATALOG" ] && >&2 echo "Unable to find catalog containing environment definition '$ENVIRONMENT'!" && exit 1 || echo $CATALOG

	if [ "$CLEAN" == "true" ]; then
		displayHeader "Delete obsolete environments ..."
		for OBSOLETE in $(az devcenter dev environment list --dev-center-name $ORGANIZATION --project-name $PROJECT --query "[?starts_with(name, '$(echo $ENVIRONMENT | tr '[:upper:]' '[:lower:]')-')].name" -o tsv | dos2unix); do
			echo "- $OBSOLETE"
			az devcenter dev environment delete --dev-center-name $ORGANIZATION --project-name $PROJECT --name $OBSOLETE --yes --no-wait &
		done; wait
	fi

	displayHeader "Deploy environment '$ENVIRONMENTNAME' ..."
	az devcenter dev environment create \
		--dev-center-name $ORGANIZATION \
		--project-name $PROJECT \
		--catalog-name $CATALOG \
		--environment-definition-name $ENVIRONMENT \
		--environment-type $ENVIRONMENTTYPE \
		--name $ENVIRONMENTNAME \
		--parameters $PARAMETERS \
		--user-id $USERID \
		$DEBUGARG

	popd > /dev/null

}

clear 

while read ENVIRONMENTPATH; do

	[[ "$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $ENVIRONMENTPATH))" | tr '[:upper:]' '[:lower:]')" ]] && deployEnvironment $ENVIRONMENTPATH

done < <(find . -type f -path './*/manifest.yaml')

