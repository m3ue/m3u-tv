import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://editor.example',
  username: 'user',
  password: 'secret',
);

class _Transport {
  final progressBodies = <Map<String, Object?>>[];

  Future<Object?> call(XtreamRequest request) async {
    if (request.action == 'update_progress') {
      progressBodies.add(Map.of(request.body));
      return null;
    }
    return <String, Object?>{
      'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
      'server_info': <String, Object?>{'timezone': 'UTC'},
      'm3u_editor': <String, Object?>{
        'version': '0.14.1',
        'watch_history': <Object?>[
          <String, Object?>{'provider': 'trakt', 'account': 'couchpotato'},
          <String, Object?>{'provider': 'simkl', 'account': null},
        ],
      },
    };
  }
}

const _progress = Progress(
  viewerId: 'viewer',
  contentType: ContentType.vod,
  streamId: 7,
  positionSeconds: 60,
);

void main() {
  late _Transport transport;
  late XtreamService service;

  setUp(() {
    transport = _Transport();
    service = XtreamService(transport: transport.call);
  });

  test('reads the accounts M3U Editor sends progress to', () async {
    final auth = await service.authenticate(_credentials);

    expect(auth.serverWatchHistory('trakt')?.account, 'couchpotato');
    expect(auth.serverWatchHistory('simkl'), isNotNull);
    expect(auth.serverWatchHistory('simkl')?.account, isNull);
    expect(auth.serverWatchHistory('other'), isNull);
  });

  test(
    'names the trackers this device scrobbles to on progress saves',
    () async {
      await service.authenticate(_credentials);

      await service.updateProgress(_progress);
      service.clientScrobblers = () => ['trakt', 'simkl'];
      await service.updateProgress(_progress);

      expect(
        transport.progressBodies.first.containsKey('client_scrobblers'),
        isFalse,
      );
      expect(transport.progressBodies.last['client_scrobblers'], 'trakt,simkl');
    },
  );
}
