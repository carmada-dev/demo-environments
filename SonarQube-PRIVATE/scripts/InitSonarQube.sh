#!/bin/bash

while getopts 'h:p:c:s:' OPT; do
    case "$OPT" in
		h)
			HOSTNAME="${OPTARG}" ;;
		p)
			PASSWORD="${OPTARG}" ;;
		c)
			CLIENTID="${OPTARG}" ;;
		s)
			CLIENTSECRET="${OPTARG}" ;;
    esac
done

function raiseError() {
	echo "$1" 1>&2 && exit 1
}

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

waitForSonarQube() {
	OPERATION_START=$EPOCHSECONDS
	OPERATION_TIMEOUT=900
	while [ true ]; do
		[ $(($EPOCHSECONDS - $OPERATION_START)) -ge $OPERATION_TIMEOUT ] && raiseError "Waiting for SonarQube to become available timed out after $OPERATION_TIMEOUT seconds."
		STATUS="$(curl -s -u admin:$PASSWORD "https://$HOSTNAME/api/system/status" | jq -r '.status')"
		[ "$STATUS" = "UP" ] && break || (echo "SonarQube status is $STATUS - retry after 10 seconds"; sleep 10)
	done
}

changeAdminPassword() {
	OPERATION_START=$EPOCHSECONDS
	OPERATION_TIMEOUT=900
	while [ true ]; do
		[ $(($EPOCHSECONDS - $OPERATION_START)) -ge $OPERATION_TIMEOUT ] && raiseError "Changing SonarQube admin password timed out after $OPERATION_TIMEOUT seconds."
		STATUSCODE="$(curl -s -w '%{http_code}' -o /dev/null -u admin:admin -X POST "https://$HOSTNAME/api/users/change_password?login=admin&previousPassword=admin&password=$PASSWORD")"
		([[ "$STATUSCODE" = 20* ]] || [[ "$STATUSCODE" = 403 ]]) && break || ( echo "Received status code $STATUSCODE - retry after 10 seconds"; sleep 10)
	done
}

restartSonarQube() {
	curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/system/restart"
	sleep 10 && waitForSonarQube
}

setSonarQubeConfigValue() {
	curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/settings/set" -H "Content-Type: application/x-www-form-urlencoded" -d "${1}"
}

urlencode() {
	jq -rn --arg x "${1}" '$x|@uri'
}

displayHeader "Changing Admin Password ..." \
	&& changeAdminPassword \
	&& restartSonarQube

displayHeader "Configure SonarQube Core ..." \
	&& waitForSonarQube \
	&& setSonarQubeConfigValue "key=sonar.core.serverBaseURL&value=$(urlencode "https://$HOSTNAME")" \
	&& restartSonarQube

displayHeader "Installing PlugIns ..." \
	&& waitForSonarQube \
	&& curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/settings/set" -H "Content-Type: application/x-www-form-urlencoded" -d "key=sonar.plugins.risk.consent&value=ACCEPTED" \
	&& curl -s -o /dev/null -u admin:$PASSWORD -X POST "https://$HOSTNAME/api/plugins/install" -H "Content-Type: application/x-www-form-urlencoded" -d "key=authaad" \
	&& restartSonarQube


displayHeader "Configure AzureAD PlugIn ..." \
	&& waitForSonarQube \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.enabled&value=true" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.clientId.secured&value=$CLIENTID" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.clientSecret.secured&value=$CLIENTSECRET" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.tenantId&value=$(az account show --query tenantId -o tsv)" \
	&& setSonarQubeConfigValue "key=sonar.auth.aad.loginStrategy&value=Same%20as%20Azure%20AD%20login" \
	&& restartSonarQube

