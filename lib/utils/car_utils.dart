class CarUtils {
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
  static int getCarKm(String response) {
    print("Entered getCarKm with response: $response");
    try {
      if (response.isEmpty) {
        print("Empty response.");
        return 0;
      }
      if (response.length >= 4) {
        print("Response length is sufficient.");
        final cleanedResponse = response
            .trim()
            .replaceAll(" ", "")
            .replaceAll(">", "")
            .replaceAll("0D", "");
        print("Cleaned response: $cleanedResponse");
        final kmInHex = cleanedResponse.substring(cleanedResponse.length - 8);
        print("KM in Hex: $kmInHex");
        final carKm = int.parse(kmInHex, radix: 16);
        print("Car KM: $carKm");
        return carKm;
      } else {
        print("Response too short for KM extraction.");
        return 0;
      }
    } catch (e) {
      print("Error parsing KM: $e");
      return 0;
    }
  }

  /// Removes all occurrences of "7E8", spaces, and ".",
  /// then strips out "21" at index 16 and "22" at index 30 (if present),
  /// and finally converts the last 17 bytes (34 hex chars) to ASCII.
  static String getCarVin(String response) {
    // Step 1: Remove "7E8", spaces, literal dots (if any).
    String cleaned = response
        .trim()
        .replaceAll("7E8", "")
        .replaceAll(" ", "")
        .replaceAll(".", "")
        .replaceAll(":", "");

    // Step 2: Remove "21" at index 16
    if (cleaned.length >= 18 && cleaned.substring(16, 18) == "21") {
      cleaned = cleaned.substring(0, 16) + cleaned.substring(18);
    }

    // Step 3: Remove "22" at index 30
    if (cleaned.length >= 32 && cleaned.substring(30, 32) == "22") {
      cleaned = cleaned.substring(0, 30) + cleaned.substring(32);
    }

    // Step 4: Keep only the last 34 characters (17 bytes)
    if (cleaned.length > 34) {
      cleaned = cleaned.substring(cleaned.length - 34);
    }

    print("Final HEX: $cleaned");

    // Convert hex → ASCII
    final asciiResult = hexToAscii(cleaned);
    print("ASCII: $asciiResult");

    return asciiResult;
  }
}
