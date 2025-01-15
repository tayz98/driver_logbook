import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_foundation/path_provider_foundation.dart'
    as ios_path_provider;
import 'package:path_provider/path_provider.dart';
import 'objectbox.g.dart';
import 'package:path_provider_android/path_provider_android.dart'
    as android_path_provider;

class ObjectBox {
  static late final Store store;

  static Future create() async {
    try {
      if (Platform.isAndroid) {
        android_path_provider.PathProviderAndroid.registerWith();
      } else if (Platform.isIOS) {
        ios_path_provider.PathProviderFoundation.registerWith();
      } else {
        throw UnsupportedError("This platform is not supported");
      }
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docsDir.path, "objectbox");
      if (Store.isOpen(dbPath)) {
        store = Store.attach(getObjectBoxModel(), dbPath);
      } else {
        store = await openStore(directory: dbPath);
      }
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }
}
