import 'dart:async';
import 'package:elogbook/widgets/check_permissions_button.dart';
import 'package:elogbook/widgets/choose_trip_mode_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'package:elogbook/widgets/trip_details_card.dart';
import 'package:elogbook/widgets/scan_devices_button.dart';

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
    ref.read(tripProvider.notifier).restoreCategory();
    //final bluetoothService = ref.read(customBluetoothServiceProvider);
    // _logSubscription = bluetoothService.logStream.listen((log) {
    //   setState(() {
    //     _logs.add(log);
    //     if (_logs.length > 15) {
    //       _logs.removeAt(0);
    //     }
    //   });
    // });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = ref.watch(customBluetoothServiceProvider);
    final trip = ref.watch(tripProvider);

    return Scaffold(
        appBar: AppBar(
          title: const Text("NovaCorp - Fahrtenbuch"),
        ),
        body: Column(
          children: [
            buildTripDetails(context, trip),
            const Spacer(),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChooseTripModeButtons(
                    initialMode: trip.tripCategoryEnum,
                    onModeChanged: (newMode) {
                      ref.read(tripProvider.notifier).changeMode(newMode);
                    },
                  ),
                ],
              ),
            ),
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
                  : Container(),
              //const Center(child: Text("No logs yet.")),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScanDevicesButton(
                onScan: () => bluetoothService.scanForDevices(),
              ),
              const SizedBox(height: 8),
              const PermissionsButton(),
            ],
          ),
        ));
  }
}
