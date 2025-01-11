import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

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
    return ElevatedButton(
      onPressed: _isRequesting ? null : _requestAllPermissions,
      child: _isRequesting
          ? const CircularProgressIndicator(color: Colors.blueAccent)
          : const Text('Request Permissions'),
    );
  }

  Future<void> _requestAllPermissions() async {
    setState(() {
      _isRequesting = true;
    });

    for (var permission in _permissions) {
      if (!await permission.isGranted) {
        await permission.request();
      }
    }

    setState(() {
      _isRequesting = false;
    });
  }
}
