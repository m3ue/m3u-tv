import 'dart:developer' as developer;

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
    // Linux's OS keyring (libsecret/gnome-keyring) can be genuinely
    // unreachable in some environments -- headless/VNC sessions whose PAM
    // stack never auto-unlocks it and that have no secret-prompter component
    // to unlock it interactively either, surfacing as a permanent
    // `PlatformException(KeyringLocked, ...)`. That's documented upstream
    // flutter_secure_storage behavior, not a transient error a retry fixes.
    // ResilientSecureStorage keeps the real OS keyring for the (common) case
    // where it works, and only degrades to plaintext file storage for the
    // (uncommon) environments where it genuinely can't be reached.
    'linux' =>
      secureStorageFactory != null
          ? secureStorageFactory()
          : ResilientSecureStorage(
              primary: FlutterSecureStorageAdapter(),
              fallback: FileSecureStorage(store: appStateStore),
              onFallback: (error) => developer.log(
                'Linux OS keyring unavailable; falling back to file-based '
                'credential storage for this session: $error',
                name: 'ProductionStorage',
                level: 900, // warning
              ),
            ),
    'android' ||
    'ios' ||
    'tvos' ||
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
