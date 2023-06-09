#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

for TEMPLATE in $(find $SCRIPT_DIR -type f -name 'azuredeploy.bicep' | dos2unix); do
	pushd $(dirname "$TEMPLATE") > /dev/null
	echo "Transpiling template in '$(pwd)' ..."
	az bicep build --file ./azuredeploy.bicep --outfile ./azuredeploy.json --only-show-errors
	popd > /dev/null
done