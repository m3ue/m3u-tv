import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/secure_storage.dart';

class ProductionStorage {
  const ProductionStorage({
    required this.appStateStore,
    required this.credentialStorage,
  });

  final PersistentJsonStore appStateStore;
  final SecureStorage credentialStorage;
}

bool shouldMigrateLegacyCredentials(String operatingSystem) =>
    operatingSystem == 'linux' || operatingSystem == 'windows';

ProductionStorage createProductionStorage({
  required String operatingSystem,
  PersistentJsonStore? persistentStore,
  SecureStorage Function()? secureStorageFactory,
}) {
  final appStateStore = persistentStore ?? PersistentJsonStore();
  final credentialStorage = switch (operatingSystem) {
    'android' ||
    'ios' ||
    'tvos' ||
    'linux' ||
    'windows' => (secureStorageFactory ?? FlutterSecureStorageAdapter.new)(),
    _ => FileSecureStorage(store: appStateStore),
  };

  return ProductionStorage(
    appStateStore: appStateStore,
    credentialStorage: credentialStorage,
  );
}

Future<void> migrateLegacyCredentials({
  required PersistentJsonStore appStateStore,
  required SecureStorage credentialStorage,
}) async {
  const credentialsKey = 'm3ue_tv_credentials';

  try {
    if (await credentialStorage.read(credentialsKey) != null) {
      await appStateStore.delete(credentialsKey);
      return;
    }

    final legacyCredentials = await appStateStore.read(credentialsKey);
    if (legacyCredentials is! String) return;

    try {
      await credentialStorage.write(credentialsKey, legacyCredentials);
    } finally {
      await appStateStore.delete(credentialsKey);
    }
  } on Object {
    // Credential migration must not block application startup.
  }
}
