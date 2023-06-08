RESET='false'
DELETE='false'

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

deployEnvironment() {

	pushd "$(dirname "$1")" > /dev/null

	displayHeader "Initialize terraform ..."
	[ -d "./.terraform" ] && terraform init -upgrade || terraform init 

	displayHeader "Validate template ..."
	terraform validate || exit

	if [ "$DELETE" = "true" ] || [ "$RESET" = "true" ]; then

		displayHeader "Deprovision environment ..."
		terraform apply -auto-approve -destroy || exit

	fi

	if [ "$DELETE" = "false" ]; then

		displayHeader "Provision environment ..."
		terraform apply -auto-approve || exit

	fi

	popd > /dev/null

}

clear 

while getopts 'e:rd' OPT; do
    case "$OPT" in
		e)
			ENVIRONMENT="${OPTARG}" ;;
		r)
			RESET='true' ;;
		d)
			DELETE='true' ;;
		*) 
			usage ;;
    esac
done


while read ENVIRONMENTPATH; do

	[[ -z "$ENVIRONMENT" || "$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $ENVIRONMENTPATH))" | tr '[:upper:]' '[:lower:]')" ]] && deployEnvironment $ENVIRONMENTPATH

done < <(find . -type f -path './*/main.tf')