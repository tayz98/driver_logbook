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
  late final Store store;
  Directory? docsDir;

  ObjectBox._create(this.store);

  static Future<ObjectBox> create() async {
    try {
      if (Platform.isAndroid) {
        android_path_provider.PathProviderAndroid.registerWith();
      } else if (Platform.isIOS) {
        ios_path_provider.PathProviderFoundation.registerWith();
      } else {
        throw UnsupportedError("This platform is not supported");
      }
      final docsDir = await getApplicationDocumentsDirectory();
      final store =
          await openStore(directory: p.join(docsDir.path, "obx-example"));
      return ObjectBox._create(store);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  static ObjectBox createFromReference(ByteData reference) {
    final store = Store.fromReference(getObjectBoxModel(), reference);
    return ObjectBox._create(store);
  }

  ByteData get storeReference => store.reference;

  Future<void> close() async {
    store.close();
  }
}
