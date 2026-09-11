using System.Text.Json;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace LogisticsFunctions;

public static class ProcessEmailAlerts
{
    [FunctionName("ProcessEmailAlerts")]
    public static void Run(
        [ServiceBusTrigger("shipment-alerts", "email-alerts", Connection = "ServiceBusConnection")] string message, ILogger log)
    {
        var alert = JsonSerializer.Deserialize<AlertEvent>(message);
        if (alert is null)
        {
            log.LogWarning("Ignoring unparseable alert message");
            return;
        }
        log.LogInformation($"Email Alert: Shipment {alert.ShipmentId} is {alert.Type}!");
    }
}
