# Logistics EDA

A learning sandbox for an event-driven logistics tracking pipeline on Azure.

A Python simulator produces shipment telemetry, Event Hubs ingests it, an Azure Function stores it in Cosmos DB and fans alerts out over Service Bus, where SQL-filtered subscriptions split the traffic between email alerts and inventory updates.

## Architecture

```
                    ┌──────────────┐   upsert   ┌───────────────┐
                    │  Cosmos DB    │◄──────────┤               │
                    │  Shipments    │            │               │
                    └──────────────┘            │  Function App │
                                                 │               │
┌─────────┐   ┌────────────┐   ┌──────────────┐ │ {ProcessTele- │
│ Producer │──►│ Event Hubs  │──►│ {ProcessTele- │ │   metry}      │
│ (Python) │   │ telemetry- │   │   metry}      │ └───────┬───────┘
└─────────┘   │ events      │   │               │         │ ServiceBusMessage
              └────────────┘   └──────────────┘   (DELAY|DELIVERED only)
                                                   │
                                        ┌──────────▼─────────┐
                                        │ SB Topic           │
                                        │ shipment-alerts    │
                                        └─────┬────────┬─────┘
                               SQL filter 'DELAY'   SQL filter 'DELIVERED'
                                        │                    │
                                 ┌──────▼─────┐      ┌───────▼──────┐
                                 │ Process    │      │ Process      │
                                 │ Email      │      │ Inventory    │
                                 │ Alerts     │      │ Updates      │
                                 └────────────┘      └──────────────┘
```

- **Producer** (`src/EventHubProducer`) — Python script, sends a random shipment payload (Id, Timestamp, coords, `Status` ∈ IN_TRANSIT / DELAY / DELIVERED) to the Event Hub every second.
- **ProcessTelemetry** — Event Hub triggered consumer; upserts to Cosmos DB, and for `DELAY` / `DELIVERED` messages sends a Service Bus message tagged with an application property `Type`.
- **ProcessEmailAlerts / ProcessInventoryUpdates** — Service Bus consumers, one per subscription. The topic-scoped SQL rules (`email-filter`: `Type = 'DELAY'`, `inventory-filter`: `Type = 'DELIVERED'`) decide which one gets a message.

## Repository layout

```
infra/                    Bicep for the real stack (RG logistics-eda-rg)
src/
  EventHubProducer/       Python simulator + uv project
  LogisticsFunctions/     .NET 8 in-process function app (3 functions)
test/                     Minimal free-stack validation (storage only)
deploy.sh                 Deploy: infra / app settings / publish
.github/workflows/deploy.yml   CI/CD (disabled until DEPLOY_ENABLED=true)
```

## Prerequisites

- Azure CLI, logged in (`az login`)
- .NET SDK 8 for the function app
- [uv](https://docs.astral.sh/uv/) for the Python producer
- `zip` (used by the deploy script)

## Deploy

```bash
./deploy.sh              # everything: infra + app settings + function publish
./deploy.sh --infra      # bicep only
./deploy.sh --app        # app settings + publish (assumes infra exists)
```

The script creates RG `logistics-eda-rg` (australiaeast by default, override with `LOCATION=...`), deploys Bicep, fetches connection strings at deploy time and writes them straight into the Function App settings — nothing secret is stored in the repo. On a TTY it prints your Event Hub connection string; in CI (non-TTY) it only prints the command to fetch it.

## Run it

```bash
# 1. one-time Python setup, then run the simulator
cd src/EventHubProducer && uv sync
EVENTHUB_CONNECTION="<connection string>" uv run python producer.py

# 2. watch the pipeline
az functionapp log tail -g logistics-eda-rg -n logistics-processor-fa
```

`ProcessEmailAlerts`/`ProcessInventoryUpdates` log only when a message's `Type` matches their subscription filter, so they show up for DELAY / DELIVERED statuses.

## CI/CD

`.github/workflows/deploy.yml` deploys on push to `main` (infra-or-app path filtered), gated by a kill switch:

1. Set repo **variables**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (values from an OIDC-federated Azure AD application — see the `github-app-auth` style setup).
2. Set `DEPLOY_ENABLED = true` **only when ready**. Until then the workflow runs but every deploy job is skipped.
3. Jobs are `changes → infra → app`, so app publish always waits for infra and aborts if infra failed.

Local `deploy.sh` is unaffected by `DEPLOY_ENABLED`.

## Teardown

```bash
az group delete -n logistics-eda-rg --no-wait -y
az group delete -n logistics-eda-test-rg --no-wait -y   # test sandbox
```

## Sandbox / try first

`test/` deploys only a storage account + blob container into `logistics-eda-test-rg` (penny-cost, portal-visible) so you can confirm `az login`, RBAC and the deploy loop before spending anything on the real stack:

```bash
cd test && ./deploy.sh
```

Approximate cost note: the real stack runs on the consumption plan and standard-tier Event Hubs / Service Bus / Cosmos (`infra/infra.bicep`); cheap for a sandbox but not free — tear it down when done.