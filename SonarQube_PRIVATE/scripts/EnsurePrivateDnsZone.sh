#!/bin/bash

function assertNotEmpty() {
	[ -z "$2" ] && echo "Variable '$1' must not be empty!" 1>&2 && exit 1
}

eval "$(jq -r '@sh "RESOURCEGROUPID=\(.RESOURCEGROUPID)"')"
assertNotEmpty 'RESOURCEGROUPID' $RESOURCEGROUPID

eval "$(jq -r '@sh "PROJECTNETWORKID=\(.PROJECTNETWORKID)"')"
assertNotEmpty 'PROJECTNETWORKID' $PROJECTNETWORKID

eval "$(jq -r '@sh "ENVIRONMENTNETWORKID=\(.ENVIRONMENTNETWORKID)"')"
assertNotEmpty 'ENVIRONMENTNETWORKID' $ENVIRONMENTNETWORKID

eval "$(jq -r '@sh "DNSZONENAME=\(.DNSZONENAME)"')"
assertNotEmpty 'DNSZONENAME' $DNSZONENAME

SUBSCRIPTION="$(echo $RESOURCEGROUPID | cut -d '/' -f3)"
RESOURCEGROUP="$(echo $RESOURCEGROUPID | cut -d '/' -f5)"

DNSZONEID=$(az network private-dns zone show --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)

if [ -z "$DNSZONEID" ]; then
	DNSZONEID=$(az network private-dns zone create --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)
	assertNotEmpty 'DNSZONEID' $DNSZONEID
fi

az network private-dns link vnet create \
	--subscription $SUBSCRIPTION \
	--resource-group $RESOURCEGROUP \
	--name $(basename $PROJECTNETWORKID) \
	--zone-name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') \
	--virtual-network $PROJECTNETWORKID \
	--registration-enabled false \
	--output none \
	--only-show-errors || exit 1

az network private-dns link vnet create \
	--subscription $SUBSCRIPTION \
	--resource-group $RESOURCEGROUP \
	--name $(basename $PROJECTNETWORKID) \
	--zone-name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') \
	--virtual-network $ENVIRONMENTNETWORKID \
	--registration-enabled false \
	--output none \
	--only-show-errors || exit 1

jq -n \
	--arg DNSZONEID "$DNSZONEID" \
	'{ DNSZONEID: $DNSZONEID }' 
