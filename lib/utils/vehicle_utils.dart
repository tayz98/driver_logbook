import 'package:flutter_dotenv/flutter_dotenv.dart';

class VehicleUtils {
  // format of map: VIN(key) : Vehicle Model(value)

// VIN is composed of 17 characters  divided into specific sections:
// 1-3: World Manufacturer Identifier (WMI)
// 4-9: Vehicle Descriptor Section (VDS)
// 10-17: Vehicle Identifier Section (VIS)

  static final Map<String, String> vehicleModels = {};

  static Future<void> initializeVehicleModels() async {
    await dotenv.load(fileName: ".env");
    vehicleModels[dotenv.get('SKODA_CITIGO_2016_VIN',
        fallback: 'UNKNOWN_VIN')] = 'Skoda Citigo 2016';
    vehicleModels[dotenv.get('BMW_F21_2013_VIN', fallback: 'UNKNOWN_VIN')] =
        'BMW F21 2013';
    // add more if needed
  }

  static String getVehicleMileageCommand(String vin) {
    String? model = vehicleModels[vin];
    switch (model) {
      case 'Skoda Citigo 2016':
        return '2210E01';
      case 'BMW F21 2013':
        throw Exception('Not implemented yet');
      default:
        throw Exception('Unknown vehicle model');
    }
  }

  /// Converts a hex string (e.g., "544D42") to its ASCII representation ("TMB").
  static String hexToAscii(String hexString) {
    final buffer = StringBuffer();

    for (var i = 0; i < hexString.length; i += 2) {
      final byteString = hexString.substring(i, i + 2);
      final byteValue = int.parse(byteString, radix: 16);
      buffer.write(String.fromCharCode(byteValue));
    }
    return buffer.toString();
  }

  static int getVehicleKm(String vin, String response) {
    String? model = vehicleModels[vin];
    switch (model) {
      case 'Skoda Citigo 2016':
        return getVehicleKmOfSkoda(response);
      case 'BMW F21 2013':
        throw Exception('Not implemented yet');
      default:
        throw Exception('Unknown vehicle model');
    }
  }

  /// Parses the last 4 hex characters of [response] into an integer.
  /// Returns 0 if parsing fails or if the response is too short.
  static int getVehicleKmOfSkoda(String response) {
    // Validate input length
    // Validate input length
    if (response.length < 8) {
      throw ArgumentError(
          "Response string is too short to extract kilometers.");
    }

    // Extract the last 8 characters (4 bytes in hexadecimal)
    String last4Bytes =
        response.substring(response.length - 8, response.length);

    print("Last 4 Bytes (Hex): $last4Bytes");

    try {
      // Convert the last 8 characters (Hex) to Decimal
      int kilometers = int.parse(last4Bytes, radix: 16);

      print("Kilometers (Decimal): $kilometers");

      // Return the result as a double
      return kilometers;
    } catch (e) {
      throw FormatException("Invalid hex value in response: $last4Bytes");
    }
  }

  static String getVehicleVin(String response) {
    // Step 1: Remove "7E8" and spaces if present
    String cleanedInput = response.replaceAll("7E8", "").replaceAll(" ", "");

    // Step 2: Split the cleaned input into 8-byte OBD packages
    List<String> packages = [];
    for (int i = 0; i < cleanedInput.length; i += 16) {
      // 8 bytes = 16 hex chars
      packages.add(cleanedInput.substring(i, i + 16));
    }

    // Step 3: Remove the frame type field (first byte) from each package
    List<String> processedPackages = packages.map((package) {
      return package.substring(2); // Remove the first byte (2 hex chars)
    }).toList();

    // Step 4: Join the cleaned packages and extract the last 17 bytes (34 hex chars)
    String combinedHex = processedPackages.join();
    String last17Bytes = combinedHex.substring(combinedHex.length - 34);

    // Step 5: Convert the last 17 bytes (34 hex chars) to ASCII
    String asciiResult = hexToAscii(last17Bytes);

    return asciiResult;
  }
}
