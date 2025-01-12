// elevated button widget

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanDevicesButton extends StatefulWidget {
  final Future<void> Function() onScan;

  const ScanDevicesButton({super.key, required this.onScan});

  @override
  ScanDevicesButtonState createState() => ScanDevicesButtonState();
}

class ScanDevicesButtonState extends State<ScanDevicesButton> {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        try {
          await widget.onScan();

          final prefs = await SharedPreferences.getInstance();
          final deviceIds = prefs.getStringList('knownRemoteIds') ?? [];

          if (deviceIds.isNotEmpty) {
            _showScanResultsDialog(deviceIds);
          } else {
            _showNoDevicesFoundDialog();
          }
        } catch (e) {
          debugPrint('Error: $e');
        }
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
          width: 1.5,
        ),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.pressed)) {
              return Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1);
            }
            return Theme.of(context).colorScheme.surface;
          },
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.pressed)) {
              return Theme.of(context).colorScheme.primary;
            }
            return Theme.of(context).colorScheme.onSurface;
          },
        ),
      ),
      child: const Text("Bluetooth-Geräte suchen und speichern"),
    );
  }

  void _showScanResultsDialog(List<String> deviceIds) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Scan-Ergebnisse'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: deviceIds
                .map(
                  (id) => ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(id),
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showNoDevicesFoundDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Keine Bluetooth-Geräte gefunden'),
          content: const Text(
              'Es wurden keine neuen Geräte gefunden. Bitte versuchen Sie es erneut.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
