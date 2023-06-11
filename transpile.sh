#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

for TEMPLATE in $(find $SCRIPT_DIR -type f -name 'azuredeploy.bicep'); do
	pushd $(dirname "$TEMPLATE") > /dev/null
	echo "Transpiling template in '$(pwd)' ..."
	az bicep build --file ./azuredeploy.bicep --outfile ./azuredeploy.json --only-show-errors
	popd > /dev/null
done

for SCRIPT in $(find $SCRIPT_DIR -type f -name '*.sh'); do
	echo "Marking script as executable '$SCRIPT' ..."
	chmod +x $SCRIPT && git update-index --chmod=+x $SCRIPT
done