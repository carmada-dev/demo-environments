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

	displayHeader "Resolve DevCenter resource group ..."
	RESOURCEGROUP="$(az resource list --resource-type 'Microsoft.DevCenter/devcenters' --query "[?name=='$ORGANIZATION']|[0].resourceGroup" -o tsv)"
	[ -z "$RESOURCEGROUP" ] && >&2 echo "Unable to find resource group containing DevCenter '$ORGANIZATION'!" && exit 1 || echo $RESOURCEGROUP

	displayHeader "Synchronize DevCenter catalogs ..."
	while read CATALOGITEM; do
		echo "- $CATALOGITEM ..."
		az devcenter admin catalog sync --dev-center $ORGANIZATION --resource-group $RESOURCEGROUP --catalog-name $CATALOGITEM &
	done < <(az devcenter admin catalog list --dev-center $ORGANIZATION --resource-group $RESOURCEGROUP --query '[].name' -o tsv) && wait

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

