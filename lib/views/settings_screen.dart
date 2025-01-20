import 'package:flutter/material.dart';
import 'package:elogbook/widgets/button_template.dart';
import 'package:elogbook/models/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends StatefulWidget {
  final Future<void> Function() onScan;
  const Settings({super.key, required this.onScan});

  @override
  SettingsState createState() => SettingsState();
}

class SettingsState extends State<Settings> {
  bool? _isServiceRunning;
  Future<void> checkService() async {
    final tempBool = await isServiceRunning;
    setState(() {
      _isServiceRunning = tempBool;
    });
  }

  @override
  void initState() {
    super.initState();
    checkService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // First Section: Service Control
                const Text(
                  'Dienststeuerung',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                CustomButton(
                    label: "Dienst starten",
                    onPressed: _isServiceRunning == false
                        ? () async {
                            setState(() {
                              _isServiceRunning = true;
                            });
                            await startBluetoothService();
                          }
                        : null),
                const SizedBox(height: 8),
                CustomButton(
                  label: "Dienst beenden",
                  onPressed: _isServiceRunning == true
                      ? () async {
                          setState(() {
                            _isServiceRunning = false;
                          });
                          await stopBluetoothService();
                        }
                      : null,
                ),
                const Divider(height: 32),

                // Second Section: Additional Settings
                const Text(
                  'Geräte und Berechtigungen',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                // Button for searching Bluetooth devices
                CustomButton(
                    label: "Bluetooth-Geräte suchen",
                    onPressed: () async {
                      try {
                        await widget.onScan();
                        if (foundDeviceIds.isNotEmpty) {
                          if (context.mounted) {
                            _showScanResultsDialog(context, foundDeviceIds);
                          }
                        } else {
                          if (context.mounted) {
                            _showNoDevicesFoundDialog(context);
                          }
                        }
                      } catch (e) {
                        debugPrint('Error: $e');
                      }
                    }),
                const SizedBox(height: 8),
                // Disable ui, category is set to business
                CustomButton(
                    label: "Berechtigungen anfordern",
                    onPressed: arePermissionsGranted
                        ? null
                        : () async {
                            await requestAllPermissions(context);
                          }),

                const SizedBox(height: 8),
                // Allow the user to see the ui and set the category for a trip
                CustomButton(
                    label: "Nutzer-Berechtigung einstellen",
                    onPressed: () {
                      _showDialogTripPermissionOptions(context);
                    }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDialogTripPermissionOptions(BuildContext context) async {
    await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Nutzerberechtigung auswählen:"),
          content: const Text(
              "Achtung: Die Standardberechtigung deaktiviert die Benutzeroberfläche!"),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('privateTripsAllowed', false);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text("Standard"),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('privateTripsAllowed', true);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text("Fortgeschritten"),
            ),
          ],
        );
      },
    );
  }

  void _showScanResultsDialog(
      BuildContext localContext, List<String> deviceIds) {
    showDialog(
      context: localContext,
      barrierDismissible: false,
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
              onPressed: () => {
                if (Navigator.canPop(context)) {Navigator.of(context).pop()}
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showNoDevicesFoundDialog(BuildContext localContext) {
    showDialog(
      context: localContext,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Keine Bluetooth-Geräte gefunden'),
          content: const Text(
              'Es wurden keine neuen Geräte gefunden. Bitte versuchen Sie es erneut.'),
          actions: [
            TextButton(
              onPressed: () => {
                if (Navigator.canPop(context)) {Navigator.of(context).pop()}
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
