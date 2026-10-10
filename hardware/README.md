# Live sensor hardware

The MATLAB app's **Live Sensor** tab reads temperature, humidity and pressure
from a Bosch **BME280** over I2C via an Arduino.

| BME280 pin | Arduino Uno / Nano |
|---|---|
| VIN | 3.3 V |
| GND | GND |
| SDA | A4 |
| SCL | A5 |

* I2C address `0x76` (tie SDO to VCC for `0x77` and change the address in the app).
* Needs the **MATLAB Support Package for Arduino Hardware**.
* Click **Detect** to find the port (works on Windows, macOS and Linux), then **Connect**.

Raw readings are converted with the Bosch datasheet compensation formulas in
`matlab/+bme280/compensate.m`.

<!-- TODO: add a photo of your wiring here: docs/images/hardware.jpg -->
