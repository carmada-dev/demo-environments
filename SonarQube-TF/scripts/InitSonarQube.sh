#!/bin/bash

while getopts 'h:p:' OPT; do
    case "$OPT" in
		h)
			HOSTNAME="${OPTARG}" ;;
		p)
			PASSWORD="${OPTARG}" ;;
    esac
done

echo "Changing Admin Password ..." && while [ true ]; do
	STATUSCODE="$(curl -s -w '%{http_code}' -o /dev/null -u admin:admin -X POST "https://$HOSTNAME/api/users/change_password?login=admin&previousPassword=admin&password=$PASSWORD")"
	([[ "$STATUSCODE" = 20* ]] || [[ "$STATUSCODE" = 403 ]]) && break || ( echo "Received status code $STATUSCODE - retry after 10 seconds"; sleep 10)
done

waitForSonarQube() {
	while [ true ]; do
		STATUS="$(curl -s -u admin:$PASSWORD "https://$HOSTNAME/api/system/status" | jq -r '.status')"
		[ "$STATUS" = "UP" ] && break || (echo "SonarQube status is $STATUS - retry after 10 seconds"; sleep 10)
	done
}

restartSonarQube() {
	curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/system/restart"
	sleep 10 && waitForSonarQube
}

setSonarQubeConfigValue() {
	curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/settings/set" -H "Content-Type: application/x-www-form-urlencoded" -d "${1}"
}

echo "Registering Application '$HOSTNAME' ..."
TENANTID=$(az account show --query tenantId -o tsv)
CLIENTID=$(az ad app create --display-name $HOSTNAME --sign-in-audience AzureADMyOrg --identifier-uris "api://$HOSTNAME" --web-home-page-url "https://$HOSTNAME" --web-redirect-uris "https://$HOSTNAME/oauth2/callback/aad" --query appId --output tsv)
CLIENTSECRET=$(az ad app credential reset --id $CLIENTID --append --display-name "ADE-$(date +%s)" --years 10 --query password --output tsv)
OBJECTID=$(az ad app show --id $CLIENTID --query objectId --output tsv)
GRAPHID=$(az ad sp list --all --query "[?appDisplayName=='Microsoft Graph'].appId | [0]" -o tsv)

echo "Granting Permission: User.Read ..."
GRAPH_USER_READ=$(az ad sp show --id $GRAPHID --query "oauth2PermissionScopes[?value=='User.Read'].id | [0]" -o tsv)
az ad app permission add --id $CLIENTID --api $GRAPHID --api-permissions $GRAPH_USER_READ=Scope

echo "Granting Permission: User.ReadBasic.All ..."
GRAPH_USER_READBASIC_ALL=$(az ad sp show --id $GRAPHID --query "oauth2PermissionScopes[?value=='User.ReadBasic.All'].id | [0]" -o tsv)
az ad app permission add --id $CLIENTID --api $GRAPHID --api-permissions $GRAPH_USER_READBASIC_ALL=Scope

echo "Ensure Packages ..." \
	&& sudo apt install -y gridsite-clients > /dev/null

echo "Configure SonarQube Core ..." \
	&& waitForSonarQube \
	&& setSonarQubeConfigValue "key=sonar.core.serverBaseURL&value=$(urlencode "https://$HOSTNAME")" \
	&& restartSonarQube

echo "Installing PlugIns ..." \
	&& waitForSonarQube \
	&& curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/settings/set" -H "Content-Type: application/x-www-form-urlencoded" -d "key=sonar.plugins.risk.consent&value=ACCEPTED" \
	&& curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/plugins/install" -H "Content-Type: application/x-www-form-urlencoded" -d "key=authaad" \
	&& restartSonarQube


echo "Configure AzureAD PlugIn ..." \
	&& waitForSonarQube \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.enabled&value=true" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.clientId.secured&value=$CLIENTID" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.clientSecret.secured&value=$CLIENTSECRET" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.tenantId&value=$TENANTID" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.loginStrategy&value=Same%20as%20Azure%20AD%20login" \
	&& restartSonarQube

