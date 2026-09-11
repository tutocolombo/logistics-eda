import datetime as dt
import json
import os
import random
import time
import uuid

from azure.eventhub import EventData, EventHubProducerClient

connection_string = os.environ.get("EVENTHUB_CONNECTION")

EVENT_HUB_NAME = "telemetry-events"
STATUSES = ["IN_TRANSIT", "DELAY", "DELIVERED"]


def make_shipment():
    return {
        "ShipmentId": "SHIP-" + uuid.uuid4().hex[:4].upper(),
        "Timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "Latitude": -33.8688 + random.random() * 0.1,
        "Longitude": 151.2093 + random.random() * 0.1,
        "Status": random.choice(STATUSES),
    }


def main():
    connection_string = os.environ.get("EVENTHUB_CONNECTION")
    assert connection_string is not None, "Set the EVENTHUB_CONNECTION environment variable to your Event Hubs namespace connection string."

    producer = EventHubProducerClient.from_connection_string(
        connection_string, eventhub_name=EVENT_HUB_NAME
    )
    try:
        while True:
            payload = json.dumps(make_shipment()).encode("utf-8")
            producer.send_batch([EventData(payload)])
            shipment = json.loads(payload)  # pyright: ignore[reportAny]
            print(f"Sent: {shipment['ShipmentId']} ({shipment['Status']})")
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        producer.close()


if __name__ == "__main__":
    main()
