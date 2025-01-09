class VehicleUtils {
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

  /// Parses the last 4 hex characters of [response] into an integer.
  /// Returns 0 if parsing fails or if the response is too short.
  static int getVehicleKm(String response) {
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
