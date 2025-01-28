import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:driver_logbook/services/http_service.dart';

/// A custom logger that prints messages locally and also sends them to a server.
class CustomLogger {
  // Create a Logger instance with PrettyPrinter for formatting.
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 50,
      colors: true,
      printEmojis: true,
    ),
  );

  /// Log a message with the desired [level].
  /// Also sends the log message to the backend via [HttpService].
  static void log(String message, [Level level = Level.debug]) {
    // Print to console (via logger)
    _logger.log(level, message);

    String serializedMessage;
    if (message is Map<String, dynamic>) {
      serializedMessage = jsonEncode(message);
    } else {
      serializedMessage = message;
    }

    // Send the log to your server
    HttpService().post(
      type: ServiceType.log,
      body: {
        'level': level.toString(),
        'message': serializedMessage,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // Convenience methods for different log levels:
  static void d(String message) => log(message, Level.debug);
  static void i(String message) => log(message, Level.info);
  static void w(String message) => log(message, Level.warning);
  static void e(String message) => log(message, Level.error);
  static void fatal(String message) => log(message, Level.fatal);
}
