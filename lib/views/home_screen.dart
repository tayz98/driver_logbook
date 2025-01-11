import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'package:elogbook/widgets/trip_details_card.dart';
import 'package:elogbook/widgets/scan_devices_button.dart';
import 'package:elogbook/widgets/check_permissions_button.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  final List<String> _logs = [];
  late final StreamSubscription<String> _logSubscription;

  @override
  void initState() {
    super.initState();
    final bluetoothService = ref.read(customBluetoothServiceProvider);
    _logSubscription = bluetoothService.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 15) {
          _logs.removeAt(0);
        }
      });
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = ref.watch(customBluetoothServiceProvider);
    final tripNotifier = ref.watch(tripProvider.notifier);

    return Scaffold(
        appBar: AppBar(
          title: const Text("NovaCorp - Driver's Logbook"),
        ),
        body: Column(
          children: [
            buildTripDetails(context, tripNotifier.trip),
            Expanded(
              child: _logs.isNotEmpty
                  ? ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_logs[index]),
                        );
                      },
                    )
                  : const Center(child: Text("No logs yet.")),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ScanDevicesButton(onPressed: bluetoothService.scanForDevices),
                  const PermissionsButton()
                ])));
  }
}
