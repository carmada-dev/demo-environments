#!/bin/bash

function raiseError() {
	echo "$1" 1>&2 && exit 1
}

function assertNotEmpty() {
	[ -z "$2" ] && raiseError "Variable '$1' must not be empty!"
}

eval "$(jq -r '@sh "RESOURCEGROUPID=\(.RESOURCEGROUPID) PROJECTNETWORKID=\(.PROJECTNETWORKID) PRIVATENETWORKID=\(.PRIVATENETWORKID) DNSZONENAME=\(.DNSZONENAME)"')"
assertNotEmpty 'RESOURCEGROUPID' $RESOURCEGROUPID
assertNotEmpty 'PROJECTNETWORKID' $PROJECTNETWORKID
assertNotEmpty 'DNSZONENAME' $DNSZONENAME

SUBSCRIPTION="$(echo $RESOURCEGROUPID | cut -d '/' -f3)"
RESOURCEGROUP="$(echo $RESOURCEGROUPID | cut -d '/' -f5)"

NETWORKIDS=( "$PROJECTNETWORKID" )
[ -z "$PRIVATENETWORKID" ] || NETWORKIDS+=( "$PRIVATENETWORKID" )

DNSZONEID=$(az network private-dns zone show --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)

if [ -z "$DNSZONEID" ]; then
	DNSZONEID=$(az network private-dns zone create --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)
	assertNotEmpty 'DNSZONEID' $DNSZONEID
fi

for NETWORKID in "${NETWORKIDS[@]}"
do
   	LINKEXISTS="$(az network private-dns link vnet list --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --zone-name $DNSZONENAME --query "[?virtualNetwork.id=='$NETWORKID'] | [0] != null")"
   	if [ "$LINKEXISTS" == "false" ]; then
		az network private-dns link vnet create \
			--subscription $SUBSCRIPTION \
			--resource-group $RESOURCEGROUP \
			--name $(basename $NETWORKID) \
			--zone-name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') \
			--virtual-network $NETWORKID \
			--registration-enabled false \
			--output none \
			--only-show-errors || raiseError "Failed to link DNS zone '$DNSZONEID' with virtual network '$NETWORKID'"
	fi
done

jq -n \
	--arg DNSZONENAME "$DNSZONENAME" \
	--arg DNSZONEID "$DNSZONEID" \
	'{ "DNSZONEID": $DNSZONEID, "DNSZONENAME": $DNSZONENAME }' 
