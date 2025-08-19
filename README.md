# electronic driver's logbook


This project introduces a cross-plattform app for iOS and Android, designed to function as an electronic driver's logbook. The app requires an initial setup, during which a specific Bluetooth background service (available on both [Android](./lib/bluetooth_task_handler.dart) and [iOS](./lib/services/ios_bluetooth_service.dart)) must be enabled via the user interface.


Using Bluetooth Low Energy (BLE), the app communicates with an installed OBD-II dongle in the vehicle. The dongle contains an ELM327 microcontroller, which supports various OBD protocols as well as the CAN bus. Through these protocols, the app can access vehicle-specific data such as the VIN (Vehicle Identification Number), average speed, and—in some cases—mileage.

Mileage data, however, is not part of the officially supported OBD-II parameters. While many manufacturers implement it for their own purposes, they often encrypt the data. To decode it, a CAN DBC file (or a custom decryption algorithm) is required in order to translate the raw CAN bus signals into physical values.

For logging mileage, the app can use three different approaches:

1. Read and decrypt the CAN-Bus
- Requires a CAN DBC file or decryption algorithm
- Not compatible with all vehicles
- Most precise and efficient method
2. Use the average speed OBD-II parameter and calculate mileage
- Universally compatible with all vehicles
- Relies on frequent polling, limited by hardware capacity
- Higher battery consumption
- Short Bluetooth interruptions can lead to inaccuracies
- short losses of bluetooth can cause unprecise results
3. Use GPS.
- Works with all vehicles
- Requires an active GPS signal
- Accuracy may vary depending on signal quality
- Can increase battery consumption depending on implementation


For testing, mileage was successfully retrieved from a Skoda vehicle. The mileage data was decrypted by reverse-engineering the Bluetooth communication of an existing diagnostic app. Support for additional vehicles can be added by extending the[vehicle_utils.dart](./lib/utils/vehicle_utils.dart) file.

A key feature of this application is its ability to run fully automatically in the background on both platforms. Apart from the initial setup, no user interaction is required.

The primary focus of the project was on functionality and usability rather than clean or optimized code.
