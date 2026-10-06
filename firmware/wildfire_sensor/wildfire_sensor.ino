#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <ArduinoJson.h>
#include "SparkFunBME280.h"
#include "secrets.h"   // WIFI_SSID, WIFI_PASSWORD, MQTT_SERVER (secrets.example.h 참고)

BME280 mySensor;

const char* ssid = WIFI_SSID;
const char* password = WIFI_PASSWORD;
const char* mqtt_server = MQTT_SERVER;

int value = 0;
float temperature = 0, humidity = 0, pressure = 0;

WiFiClient wifiClient;
PubSubClient client(wifiClient);

long lastMsg = 0;

DynamicJsonDocument doc(1024);


void setup() {
  Serial.begin(115200);
  pinMode(15, OUTPUT);

  if(mySensor.beginI2C() == false) {
    Serial.println("[ERROR] The sensor did not respond");
    while(1);
  }

  setup_wifi();
  client.setServer(mqtt_server, 1883);
}

void setup_wifi() {
  Serial.print("[LOG] Connecting to WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
    Serial.println("[LOG] WiFi connected");
    Serial.println("[LOG] IP address: ");
    Serial.println(WiFi.localIP());
}

void reconnect() {
  while (!client.connected()) {
      Serial.print("[LOG] Attempting MQTT connection...");
      String client_id = "MQTT_FX_Client";
        client_id += String(WiFi.macAddress());
      Serial.printf("The client %s connects to mosquitto mqtt broker\n", client_id.c_str());

    if (client.connect(client_id.c_str())) {    
      Serial.println("[LOG] connected");
     } 

    else {
      Serial.print("[LOG] failed, rc=");
      Serial.print(client.state());
      Serial.println(" try again in 5 seconds");
      delay(5000);
      }
   }
}

void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

long now = millis();
  if (now - lastMsg > 2000) {
    lastMsg = now;
    
    // BME280 온도
    char tempString[10];
    temperature = mySensor.readTempC()-5.0;
    dtostrf(temperature, 1, 2, tempString);
    Serial.print("[LOG] Temperature: ");
    Serial.println(tempString);
    client.publish("esp32/temperature1", tempString);

    // BME280 습도
    char humiString[10];
    humidity = mySensor.readFloatHumidity();
    dtostrf(humidity, 1, 2, humiString);
    Serial.print("[LOG] Humidity: ");
    Serial.println(humiString);
    client.publish("esp32/humidity1", humiString);

    // BME280 기압
    char presString[10];
    pressure = mySensor.readFloatPressure() / 100.0; // Pa to hPa
    dtostrf(pressure, 1, 2, presString);
    Serial.print("[LOG] pressure: ");
    Serial.println(presString);
    client.publish("esp32/pressure1", presString);

    Serial.println(); 
  }
}
