#!/bin/bash

set -euo pipefail

eval "$(jq -r '@sh "RESOURCEGROUPID=\(.RESOURCEGROUPID)"')"
eval "$(jq -r '@sh "PROJECTNETWORKID=\(.PROJECTNETWORKID)"')"
eval "$(jq -r '@sh "ENVIRONMENTNETWORKID=\(.ENVIRONMENTNETWORKID)"')"
eval "$(jq -r '@sh "DNSZONENAME=\(.DNSZONENAME)"')"

SUBSCRIPTION="$(echo $RESOURCEGROUPID | cut -d '/' -f3)"
RESOURCEGROUP="$(echo $RESOURCEGROUPID | cut -d '/' -f5)"

DNSZONEID=$(az network private-dns zone show --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)

if [ -z "$DNSZONEID" ]; then
	DNSZONEID=$(az network private-dns zone create --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --query id -o tsv --only-show-errors 2> /dev/null)
fi

az network private-dns link vnet create --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(basename $PROJECTNETWORKID) --zone-name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --virtual-network $PROJECTNETWORKID -e false > /dev/null
az network private-dns link vnet create --subscription $SUBSCRIPTION --resource-group $RESOURCEGROUP --name $(basename $ENVIRONMENTNETWORKID) --zone-name $(echo $DNSZONENAME | tr '[:upper:]' '[:lower:]') --virtual-network $ENVIRONMENTNETWORKID -e false > /dev/null

jq -n --arg id "$DNSZONEID" '{ DNSZONEID: $id }' 
