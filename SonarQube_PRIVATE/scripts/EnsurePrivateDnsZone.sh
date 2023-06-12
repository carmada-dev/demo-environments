#!/bin/bash

function assertNotEmpty() {
	[ -z "$2" ] && echo "Variable '$1' must not be empty!" 1>&2 && exit 1
}

eval "$(jq -r '@sh "RESOURCEGROUPID=\(.RESOURCEGROUPID) PROJECTNETWORKID=\(.PROJECTNETWORKID) ENVIRONMENTNETWORKID=\(.ENVIRONMENTNETWORKID) DNSZONENAME=\(.DNSZONENAME)"')"
assertNotEmpty 'RESOURCEGROUPID' $RESOURCEGROUPID
assertNotEmpty 'PROJECTNETWORKID' $PROJECTNETWORKID
assertNotEmpty 'ENVIRONMENTNETWORKID' $ENVIRONMENTNETWORKID
assertNotEmpty 'DNSZONENAME' $DNSZONENAME

SUBSCRIPTION="$(echo $RESOURCEGROUPID | cut -d '/' -f3)"
RESOURCEGROUP="$(echo $RESOURCEGROUPID | cut -d '/' -f5)"
NETWORKIDS=( "$PROJECTNETWORKID" "$ENVIRONMENTNETWORKID" )
DNSZONEID=$(az network private-dns zone show --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)

if [ -z "$DNSZONEID" ]; then
	DNSZONEID=$(az network private-dns zone create --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)
	assertNotEmpty 'DNSZONEID' $DNSZONEID
fi

for NETWORKID in "${NETWORKIDS[@]}"
do
   	LINKEXISTS="$(az network private-dns link vnet list --resource-group prj-bumpwatch-pl --zone-name privatelink.azurewebsites.net --query "[?virtualNetwork.id=='$NETWORKID'] | [0] != null")"
   	if [ "$LINKEXISTS" == "true" ]; then
		az network private-dns link vnet create \
			--subscription $SUBSCRIPTION \
			--resource-group $RESOURCEGROUP \
			--name $(basename $PROJECTNETWORKID) \
			--zone-name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') \
			--virtual-network $NETWORKID \
			--registration-enabled false \
			--output none \
			--only-show-errors 2> /dev/null
	fi
done

jq -n \
	--arg DNSZONENAME "$DNSZONENAME" \
	--arg DNSZONEID "$DNSZONEID" \
	'{ DNSZONEID: "$DNSZONEID", DNSZONENAME: "$DNSZONENAME" }' 
