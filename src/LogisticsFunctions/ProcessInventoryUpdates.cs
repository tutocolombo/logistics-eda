using System.Text.Json;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace LogisticsFunctions;

public static class ProcessInventoryUpdates
{
    [FunctionName("ProcessInventoryUpdates")]
    public static void Run(
        [ServiceBusTrigger("shipment-alerts", "inventory-updates", Connection = "ServiceBusConnection")] string message, ILogger log)
    {
        var alert = JsonSerializer.Deserialize<AlertEvent>(message);
        if (alert is null)
        {
            log.LogWarning("Ignoring unparseable alert message");
            return;
        }
        log.LogInformation($"Inventory Update: Shipment {alert.ShipmentId} is {alert.Type}!");
    }
}
