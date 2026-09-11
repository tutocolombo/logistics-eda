#!/usr/bin/env bash
# Deploys the logistics EDA sample to Azure: infra + function app + app settings.
#
# Modes:
#   ./deploy.sh           all    - infra + app settings + publish (default)
#   ./deploy.sh --infra   infra  - bicep only (stops before app settings/publish)
#   ./deploy.sh --app     app    - app settings + publish (assumes infra exists)
#
# Secret-free script. Connection strings are fetched from `az` at deploy time and
# written straight into the Function App settings - nothing is stored in this repo.
#
# Prereqs: az CLI (logged in). Live connection strings are printed
# only on an interactive terminal; otherwise generic instructions are shown.

set -euo pipefail

MODE="${1:-all}"
case "$MODE" in
  all|infra|app) ;;
  *) echo "usage: $0 [--infra|--app]" >&2; exit 2 ;;
esac

RG="logistics-eda-rg"
LOCATION="${LOCATION:-australiaeast}"
FUNC_APP="logistics-processor-fa"
EH_NS="logistics-events-ns"
SB_NS="logistics-alerts-ns"
COSMOS_ACCT="logistics-state-db"

echo "== Creating resource group (no-op if it exists) =="
az group create --name "$RG" --location "$LOCATION" --output none

if [[ "$MODE" != "app" ]]; then
  echo "== Deploying bicep infra =="
  az deployment group create \
    --resource-group "$RG" \
    --template-file infra/infra.bicep \
    --output none
fi

if [[ "$MODE" == "infra" ]]; then
  echo
  echo "== Infra deployed. App settings + publish skipped (--infra). =="
  echo "Run ./deploy.sh --app to configure and publish the function app."
  exit 0
fi

echo "== Fetching connection strings =="
EH=$(az eventhubs namespace authorization-rule keys list \
  -g "$RG" -n "$EH_NS" -n RootManageSharedAccessKey \
  --query "primaryConnectionString" -o tsv)
SB=$(az servicebus namespace authorization-rule keys list \
  -g "$RG" -n "$SB_NS" -n RootManageSharedAccessKey \
  --query "primaryConnectionString" -o tsv)
COSMOS_KEY=$(az cosmosdb keys list \
  -g "$RG" -n "$COSMOS_ACCT" \
  --query "primaryMasterKey" -o tsv)
COSMOS_CONN="AccountEndpoint=https://${COSMOS_ACCT}.documents.azure.com/;AccountKey=${COSMOS_KEY};"

echo "== Writing app settings =="
az functionapp config appsettings set \
  --resource-group "$RG" \
  --name "$FUNC_APP" \
  --settings "EventHubConnection=$EH" "ServiceBusConnection=$SB" "CosmosDBConnection=$COSMOS_CONN" \
  --output none

echo "== Publishing function app (zip deploy) =="
command -v zip >/dev/null || { echo "error: 'zip' is required"; exit 1; }
PUB_DIR=$(mktemp -d)
ZIP="${PUB_DIR}.zip"
dotnet publish src/LogisticsFunctions/LogisticsFunctions.csproj -c Release -o "$PUB_DIR" --nologo >/dev/null
(cd "$PUB_DIR" && zip -qr "$ZIP" .)
az functionapp deployment source config-zip \
  --resource-group "$RG" \
  --name "$FUNC_APP" \
  --src "$ZIP" \
  --output none
rm -rf "$PUB_DIR" "$ZIP"

echo
echo "Done."
if [[ "$MODE" == "app" ]]; then
  echo "Function app published."
fi
if [[ -t 1 ]]; then
  echo "Run the simulator:"
  echo "  EVENTHUB_CONNECTION=\"$EH\" uv run --directory src/EventHubProducer python producer.py"
else
  echo "Get the Event Hub connection string for the simulator with:"
  echo "  az eventhubs namespace authorization-rule keys list -g $RG -n $EH_NS -n RootManageSharedAccessKey --query primaryConnectionString -o tsv"
fi
echo "Watch logs:"
echo "  az functionapp log tail -g $RG -n $FUNC_APP"
