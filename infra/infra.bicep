param location string = 'australiaeast'

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2022-10-01-preview' = {
  name: 'logistics-events-ns'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2022-10-01-preview' = {
  name: 'telemetry-events'
  parent: eventHubNamespace
  properties: {
    partitionCount: 4
    messageRetentionInDays: 1
  }
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'logistics-alerts-ns'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  name: 'shipment-alerts'
  parent: serviceBusNamespace
}

resource emailAlertsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  name: 'email-alerts'
  parent: serviceBusTopic
}

resource emailAlertsRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  name: 'email-filter'
  parent: emailAlertsSubscription
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: '''
Type = 'DELAY'
'''
    }
  }
}

resource inventoryUpdatesSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  name: 'inventory-updates'
  parent: serviceBusTopic
  properties: {}
}

resource inventoryUpdatesRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  name: 'inventory-filter'
  parent: inventoryUpdatesSubscription
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: '''
Type = 'DELIVERED'
'''
    }
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: 'logistics-state-db'
  location: location
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
  }
}

resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-08-15' = {
  name: 'ShipmentDB'
  parent: cosmosDbAccount
  properties: {
    resource: {
      id: 'ShipmentDB'
    }
  }
}

resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-08-15' = {
  name: 'Shipments'
  parent: cosmosDbDatabase
  properties: {
    resource: {
      id: 'Shipments'
      partitionKey: {
        paths: [
          '/shipmentId'
        ]
        kind: 'Hash'
      }
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'logisticsstorage'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'logistics-processor-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: 'logistics-processor-fa'
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
      ]
    }
  }
}