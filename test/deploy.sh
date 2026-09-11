#!/usr/bin/env bash
# Minimal test deploy: RG + storage account + blob container.
# Costs ~nothing (Standard_LRS storage). Everything shows up in the portal.
#
# Prereqs: az CLI, logged in.
# Tear down when done:  az group delete -n logistics-eda-test-rg --no-wait -y

set -euo pipefail

RG="logistics-eda-test-rg"
LOCATION="${LOCATION:-australiaeast}"

echo "== Creating resource group (no-op if it exists) =="
az group create --name "$RG" --location "$LOCATION" --output none

echo "== Deploying bicep =="
az deployment group create \
  --resource-group "$RG" \
  --template-file infra.bicep \
  --output table

SUB=$(az account show --query id -o tsv)
echo
echo "Deployed. See it in the portal:"
echo "  https://portal.azure.com/#@/subscriptions/${SUB}/resourceGroups/${RG}/overview"
echo
echo "Quick verify:"
echo "  az storage account list -g $RG -o table"
echo "  az storage container list --account-name <STORAGE_NAME>"
echo
echo "Tear down:"
echo "  az group delete -n $RG --no-wait -y"