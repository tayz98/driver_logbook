import 'package:intl/intl.dart';

class Helper {
  static String formatDateString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Ungültiges Datum';

    // Clean up the raw string (trim whitespace, etc.),
    // then parse as DateTime. Return null if invalid.
    DateTime? parsed = _normalizeAndParseDateTime(raw);
    if (parsed == null) {
      return 'Ungültiges Datum';
    }

    // Convert that parsed DateTime into a nice formatted string
    return DateFormat('dd.MM.yyyy HH:mm').format(parsed);
  }

// This function tries to handle some common formatting pitfalls
  static DateTime? _normalizeAndParseDateTime(String raw) {
    String input = raw.trim();

    // Example: if we might have 7 fraction digits (e.g. .1234567),
    // limit it to 6 because Dart can parse up to microseconds.
    final dotIndex = input.indexOf('.');
    if (dotIndex != -1) {
      final fractionPart =
          input.substring(dotIndex + 1).split(RegExp(r'[^0-9]')).first;
      if (fractionPart.length > 6) {
        final truncatedFraction = fractionPart.substring(0, 6);
        // Rebuild the string with up to 6 fraction digits
        input = input.replaceFirst(
          '.$fractionPart',
          '.$truncatedFraction',
        );
      }
    }

    // Attempt to parse with Dart's built-in parser
    return DateTime.tryParse(input);
  }

  static String formatTripInfo(String tripStatus) {
    switch (tripStatus) {
      case 'TripStatus.notStarted':
        return 'Fahrtaufzeichnung wartet auf Start';
      case 'TripStatus.inProgress':
        return 'Fahrt läuft';
      case 'TripStatus.finished':
        return 'Fahrt beendet';
      case 'TripStatus.cancelled':
        return 'Fahrt abgebrochen';
      default:
        return 'Unbekannter Status';
    }
  }

  static String formatCategory(String category) {
    switch (category) {
      case 'TripCategory.business':
        return 'Geschäftlich';
      case 'TripCategory.private':
        return 'Privat';
      case 'TripCategory.commute':
        return 'Arbeitsweg';
      default:
        return 'Unbekannte Kategorie';
    }
  }
}
