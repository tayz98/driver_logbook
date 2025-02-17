import 'dart:async';

import 'package:driver_logbook/models/telemetry_event.dart';

class TelemetryBus {
  TelemetryBus._internal();
  static final TelemetryBus _instance = TelemetryBus._internal();
  factory TelemetryBus() => _instance;

  final _controller = StreamController<TelemetryEvent>.broadcast();

  Stream<TelemetryEvent> get stream => _controller.stream;
  void publish(TelemetryEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}
