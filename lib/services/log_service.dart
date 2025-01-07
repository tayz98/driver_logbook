import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static File? _logFile;

  static Future<void> initializeLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/app_logs.txt');
    if (!(await _logFile!.exists())) {
      await _logFile!.create();
    }
  }

  static Future<void> appendLog(String log) async {
    if (_logFile != null) {
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!
          .writeAsString('$timestamp: $log\n', mode: FileMode.append);
    }
  }
}
