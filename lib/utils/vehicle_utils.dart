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
  static double getVehicleKm(String response) {
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
      return kilometers.toDouble();
    } catch (e) {
      throw FormatException("Invalid hex value in response: $last4Bytes");
    }
  }

  /// Removes all occurrences of "7E8", spaces, and ".",
  /// then strips out "21" at index 16 and "22" at index 30 (if present),
  /// and finally converts the last 17 bytes (34 hex chars) to ASCII.
  static String getCarVin(String response) {
    // Remove any frame headers like 10, 21, 22, etc.
    final cleanedResponse = _removeFrameIndicators(response);

    print("Cleaned HEX (without frame indicators): $cleanedResponse");

    // Convert cleaned HEX to ASCII
    final asciiResult = hexToAscii(cleanedResponse);

    print("ASCII: $asciiResult");

    return asciiResult.trim(); // Trim to remove any trailing spaces
  }

  // Helper method to remove frame indicators
  static String _removeFrameIndicators(String hexResponse) {
    const int frameSize = 16; // Each frame is 16 hex characters (8 bytes)
    final buffer = StringBuffer();

    for (int i = 0; i < hexResponse.length; i += frameSize) {
      // Extract the current frame
      final frame = hexResponse.substring(
        i,
        (i + frameSize > hexResponse.length)
            ? hexResponse.length
            : i + frameSize,
      );

      // Skip the first 2 characters (frame indicator) and append the rest
      buffer.write(frame.substring(2));
    }

    return buffer.toString(); // Return the cleaned response
  }
}
