DEBUG="false"

while getopts 'o:p:e:t:d' OPT; do
    case "$OPT" in
		o)
			ORGANIZATION="${OPTARG}" ;;
		p)
			PROJECT="${OPTARG}" ;;
		e)
			ENVIRONMENT="${OPTARG}" ;;
		t)
			ENVIRONMENTTYPE="${OPTARG}" ;;
		d)
			DEBUG="true" ;;
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
	while read PRINCIPALID; do
		echo "- $PRINCIPALID ..."
		APPLICATIONDEVELOPER_ROLEID="cf1c38e5-3621-4004-a7cb-879624dced7c"
		az rest \
    		--method post \
    		--uri https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments \
    		--headers "{ 'content-type': 'application/json' }" \
    		--body "{ '@odata.type': '#microsoft.graph.unifiedRoleAssignment', 'roleDefinitionId': '$APPLICATIONDEVELOPER_ROLEID', 'principalId': '$PRINCIPALID', 'directoryScopeId': '/' }" > /dev/null
	done < <(az devcenter admin project-environment-type list --project-name $PROJECT --resource-group $RESOURCEGROUP_DEVPROJECT --query '[].identity.principalId' -o tsv) && sleep 30

	displayHeader "Resolve catalog name ..."
	CATALOG="$(az devcenter dev environment-definition list --dev-center-name $ORGANIZATION --project-name $PROJECT --query "[?name=='$ENVIRONMENT']|[0].catalogName" -o tsv)"
	[ -z "$CATALOG" ] && >&2 echo "Unable to find catalog containing environment definition '$ENVIRONMENT'!" && exit 1 || echo $CATALOG

	displayHeader "Deploy environment '$ENVIRONMENTNAME' ..."
	az devcenter dev environment create \
		--dev-center-name $ORGANIZATION \
		--project-name $PROJECT \
		--catalog-name $CATALOG \
		--environment-definition-name $ENVIRONMENT \
		--environment-type $ENVIRONMENTTYPE \
		--name $ENVIRONMENTNAME \
		--parameters $PARAMETERS \
		$DEBUGARG


	popd > /dev/null

}

clear 

while read ENVIRONMENTPATH; do

	[[ "$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $ENVIRONMENTPATH))" | tr '[:upper:]' '[:lower:]')" ]] && deployEnvironment $ENVIRONMENTPATH

done < <(find . -type f -path './*/main.tf')

