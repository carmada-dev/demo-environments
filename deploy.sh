RESET='false'
DELETE='false'
PLAN='false'

while getopts 's:e:prd' OPT; do
    case "$OPT" in
		s)
			SUBSCRIPTION="${OPTARG}" ;;
		e)
			ENVIRONMENT="${OPTARG}" ;;
		p)
			PLAN='true' ;;
		r)
			RESET='true' ;;
		d)
			DELETE='true' ;;

    esac
done

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

deployEnvironment() {

	pushd "$(dirname "$1")" > /dev/null

	VAR_ARGS=(
		"$([ -f './development.tfvars' ] && echo '-var-file=./development.tfvars' || echo '')"
		"-var=resource_group_name=$(basename "$PWD")"
	)

	displayHeader "Initialize terraform ..."
	[ -d "./.terraform" ] && terraform init -upgrade || terraform init 

	displayHeader "Validate template ..."
	terraform validate || exit

	if [ "$PLAN" = "true" ]; then

		displayHeader "Plan provisioning ..."
		terraform plan $(printf " %s" "${VAR_ARGS[@]}") || exit

	else

		if [ "$DELETE" = "true" ] || [ "$RESET" = "true" ]; then

			displayHeader "Deprovision environment ..."
			terraform apply -auto-approve -destroy $(printf " %s" "${VAR_ARGS[@]}") || exit

		fi

		if [ "$DELETE" = "false" ]; then

			displayHeader "Ensure environment RG ..."
			az group create --name $(basename "$PWD") --location 'West Europe' --query 'id' -o tsv

			displayHeader "Provision environment ..."
			terraform apply -auto-approve $(printf " %s" "${VAR_ARGS[@]}") || exit

		fi
	fi 

	popd > /dev/null

}

clear 

BASE_SUBSCRIPTION=$(az account show --query id -o tsv)

if [ ! -z "$SUBSCRIPTION" ]; then
	displayHeader "Switching Subscription ..."
	az account set -n $SUBSCRIPTION && az account show --query name -o tsv
fi

while read ENVIRONMENTPATH; do

	[[ -z "$ENVIRONMENT" || "$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $ENVIRONMENTPATH))" | tr '[:upper:]' '[:lower:]')" ]] && deployEnvironment $ENVIRONMENTPATH

done < <(find . -type f -path './*/main.tf')

if [ "$BASE_SUBSCRIPTION" != "$(az account show --query id -o tsv)" ]; then
	displayHeader "Switching Subscription ..."
	az account set -n $BASE_SUBSCRIPTION --query name -o tsv
fi