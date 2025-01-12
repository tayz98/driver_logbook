import 'package:elogbook/models/trip_category.dart';
import 'package:intl/intl.dart';

class Helper {
  static Future<String> formatDateString(String? raw) async {
    if (raw == null || raw.trim().isEmpty) {
      return 'Ungültiges Datum';
    }

    DateTime? parsed = _normalizeAndParseDateTime(raw);
    if (parsed == null) {
      return 'Ungültiges Datum';
    }

    return DateFormat('dd.MM.yyyy HH:mm').format(parsed);
  }

  static DateTime? _normalizeAndParseDateTime(String raw) {
    String input = raw.trim();

    // Adjust for fractional seconds if necessary
    final dotIndex = input.indexOf('.');
    if (dotIndex != -1) {
      final fractionPart =
          input.substring(dotIndex + 1).split(RegExp(r'[^0-9]')).first;

      if (fractionPart.length > 6) {
        final truncatedFraction = fractionPart.substring(0, 6);
        input = input.replaceFirst(
          '.$fractionPart',
          '.$truncatedFraction',
        );
      }
    }

    try {
      return DateTime.parse(input);
    } catch (e) {
      // Fallback to more lenient parsing
      print('DateTime.parse failed for input: $input');
      return null;
    }
  }

  static String tripCategoryToDisplay(TripCategory category) {
    switch (category) {
      case TripCategory.private:
        return "Privat";
      case TripCategory.business:
        return "Geschäftlich";
      case TripCategory.commute:
        return "Arbeitsweg";
    }
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
