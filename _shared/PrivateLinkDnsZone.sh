DNSZoneId=$(az network private-dns zone show --subscription $Subscription --resource-group $ResourceGroup --name $(echo $DNSZoneName | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)
if [ -z "$DNSZoneId" ]; then
	DNSZoneId=$(az network private-dns zone create --subscription $Subscription --resource-group $ResourceGroup --name $(echo $DNSZoneName | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)
	NetworkId=$(az tag list --resource-id "/subscriptions/$Subscription/resourcegroups/$ResourceGroup" --query 'properties.tags.ProjectNetworkId' -o tsv)
	az network private-dns link vnet create --subscription $Subscription --resource-group $ResourceGroup --name $(basename $NetworkId) --zone-name $(echo $DNSZoneName | tr '[:upper:]' '[:lower:]') --virtual-network $NetworkId -e false
fi
jq -n --arg id "$DNSZoneId" '{ DNSZoneId: $id }' >  $AZ_SCRIPTS_OUTPUT_PATH