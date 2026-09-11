using System.Text.Json;
using Azure.Messaging.EventHubs;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace LogisticsFunctions;

public static class ProcessTelemetry
{
    private static readonly CosmosClient CosmosClient = new(GetRequiredSetting("CosmosDBConnection"));
    private static readonly ServiceBusClient ServiceBusClient = new(GetRequiredSetting("ServiceBusConnection"));
    private static readonly ServiceBusSender ServiceBusSender = ServiceBusClient.CreateSender("shipment-alerts");

    [FunctionName("ProcessTelemetry")]
    public static async Task Run(
        [EventHubTrigger("telemetry-events", Connection = "EventHubConnection")] EventData[] events, ILogger log)
    {
        foreach (var eventData in events)
        {
            var shipment = eventData.EventBody.ToObjectFromJson<ShipmentEvent>();
            if (shipment is null || string.IsNullOrWhiteSpace(shipment.ShipmentId))
            {
                log.LogWarning("Skipping invalid telemetry event");
                continue;
            }

            shipment.Id ??= shipment.ShipmentId;
            await CosmosClient.GetContainer("ShipmentDB", "Shipments").UpsertItemAsync(shipment);

            if (shipment.Status is "DELAY" or "DELIVERED")
            {
                var alert = new AlertEvent
                {
                    ShipmentId = shipment.ShipmentId,
                    Type = shipment.Status,
                    Timestamp = shipment.Timestamp
                };

                var message = new ServiceBusMessage(JsonSerializer.SerializeToUtf8Bytes(alert));
                message.ApplicationProperties["Type"] = alert.Type;
                await ServiceBusSender.SendMessageAsync(message);
            }
        }
    }

    private static string GetRequiredSetting(string name) =>
        Environment.GetEnvironmentVariable(name)
        ?? throw new InvalidOperationException($"Missing app setting: '{name}'. Set it in local.settings.json or Function App application settings.");
}

public class ShipmentEvent
{
    public string? Id { get; set; }
    public string? ShipmentId { get; set; }
    public DateTime Timestamp { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public string? Status { get; set; }
}

public class AlertEvent
{
    public string? ShipmentId { get; set; }
    public string? Type { get; set; }
    public DateTime Timestamp { get; set; }
}
