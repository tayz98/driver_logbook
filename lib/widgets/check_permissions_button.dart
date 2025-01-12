import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:elogbook/notification_configuration.dart';

class PermissionsButton extends StatefulWidget {
  const PermissionsButton({super.key});

  @override
  PermissionsButtonState createState() => PermissionsButtonState();
}

class PermissionsButtonState extends State<PermissionsButton> {
  bool _isRequesting = false;

  // TODO: check for iOS
  final List<Permission> _permissions = [
    Permission.location,
    Permission.locationAlways,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    //Permission.backgroundRefresh, // TODO: check if this is needed
  ];

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
        onPressed: _isRequesting ? null : _requestAllPermissions,
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
        child: _isRequesting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text('Berechtigungen anfordern und speichern'));
  }

  Future<void> _requestAllPermissions() async {
    setState(() {
      _isRequesting = true;
    });

    bool allGranted = true;

    for (var permission in _permissions) {
      if (!await permission.isGranted) {
        final status = await permission.request();
        if (status != PermissionStatus.granted) {
          allGranted = false;
        }
      }
    }

    await requestNotificationPermission();

    if (Platform.isAndroid || Platform.isIOS) {
      final bool notificationGranted = await checkNotificationPermission();
      if (!notificationGranted) {
        allGranted = false;
      }
    }

    setState(() {
      _isRequesting = false;
    });

    if (allGranted) {
      _showPermissionsGrantedDialog();
    } else {
      _showPermissionsDeniedDialog();
    }
  }

  void _showPermissionsGrantedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Berechtigungen wurden gewährt'),
          content: const Text(
            'Alle Berechtigungen wurden gewährt. Sie können jetzt fortfahren.',
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

  void _showPermissionsDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Berechtigungen wurden verweigert'),
          content: const Text(
            'Einige Berechtigungen wurden verweigert. Bitte gewähren Sie alle Berechtigungen, um fortzufahren.',
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
}
