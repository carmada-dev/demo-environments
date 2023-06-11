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

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

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

displayHeader "Changing Admin Password ..." && while [ true ]; do
	STATUSCODE="$(curl -s -w '%{http_code}' -o /dev/null -u admin:admin -X POST "https://$HOSTNAME/api/users/change_password?login=admin&previousPassword=admin&password=$PASSWORD")"
	([[ "$STATUSCODE" = 20* ]] || [[ "$STATUSCODE" = 403 ]]) && break || ( echo "Received status code $STATUSCODE - retry after 10 seconds"; sleep 10)
done

displayHeader "Ensure Packages ..." \
	&& sudo apt install -y gridsite-clients > /dev/null

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

