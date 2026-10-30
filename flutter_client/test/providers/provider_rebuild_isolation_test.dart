import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';

/// AppStateController is a single ChangeNotifier with dozens of
/// notifyListeners() call sites (EPG sweep chunks, DVR polling, progress
/// saves, ...). Every derived provider re-runs on each of them, and widgets
/// stay put only because Riverpod drops an update whose value is `==` to the
/// previous one. That holds only while each getter behind these providers
/// returns its cached instance: a getter that builds a fresh List/Set per
/// call would rebuild every watcher on every unrelated notification.
void main() {
  final providers = <String, ProviderListenable<Object?>>{
    'liveChannelsProvider': liveChannelsProvider,
    'liveCategoriesProvider': liveCategoriesProvider,
    'vodCategoriesProvider': vodCategoriesProvider,
    'seriesCategoriesProvider': seriesCategoriesProvider,
    'catalogRepositoryProvider': catalogRepositoryProvider,
    'isLoadingContentProvider': isLoadingContentProvider,
    'isConfiguredProvider': isConfiguredProvider,
    'isBootstrappingProvider': isBootstrappingProvider,
    'progressListProvider': progressListProvider,
    'dvrRecordingsProvider': dvrRecordingsProvider,
    'dvrStorageInfoProvider': dvrStorageInfoProvider,
    'dvrSeriesRulesProvider': dvrSeriesRulesProvider,
    'recordingChannelIdsProvider': recordingChannelIdsProvider,
    'sourceLabelProvider': sourceLabelProvider,
    'sourceErrorProvider': sourceErrorProvider,
    'hasDvrFeatureProvider': hasDvrFeatureProvider,
    'hasRequestsFeatureProvider': hasRequestsFeatureProvider,
    'requestsCapabilityProvider': requestsCapabilityProvider,
    'mediaRequestsProvider': mediaRequestsProvider,
  };

  test('an unrelated notification reaches no derived-provider listener', () {
    final controller = AppStateController();
    final container = ProviderContainer(
      overrides: [overrideAppState(controller)],
    );
    addTearDown(container.dispose);
    addTearDown(controller.dispose);

    final notified = <String>[];
    for (final MapEntry(key: name, value: provider) in providers.entries) {
      container.listen(provider, (_, _) => notified.add(name));
    }

    for (var i = 0; i < 3; i++) {
      // Stands in for any of the controller's notifications that leave these
      // values untouched (an EPG sweep chunk, a DVR poll with no change).
      controller.notifyListeners();
      container.read(liveChannelsProvider);
    }

    expect(notified, isEmpty);
  });
}
