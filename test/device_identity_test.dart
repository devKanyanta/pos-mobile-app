import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kantemba/core/api/api_client.dart';
import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/sync/device_identity.dart';
import 'package:kantemba/data/local/local_store.dart';
import 'package:kantemba/data/services/sync_api.dart';

import 'support/fake_server.dart';

void main() {
  sqfliteFfiInit();

  late LocalStore store;
  late FakeServer server;

  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    server = FakeServer();
  });

  tearDown(() => store.close());

  SyncApi api() => SyncApi(
    ApiClient(
      baseUrl: 'http://till.test/api/v1',
      tokenProvider: () async => 't',
      httpClient: server.client,
    ),
  );

  group('DeviceIdentity', () {
    test('deviceId is created once and stays stable', () async {
      final identity = DeviceIdentity(store.meta);
      final first = await identity.deviceId();
      expect(first, startsWith('KT-'));
      expect(await identity.deviceId(), first);
      expect(await DeviceIdentity(store.meta).deviceId(), first);
    });

    test('registers once per base URL', () async {
      final identity = DeviceIdentity(store.meta);
      expect(
        await identity.ensureRegistered(
          api(),
          baseUrl: 'http://a',
          name: 'Till',
          model: 'android',
          appVersion: '1.0.0',
        ),
        isTrue,
      );
      expect(await identity.ensureRegistered(api(), baseUrl: 'http://a'),
          isTrue);

      final posts = server.posts('/sync/devices/register').toList();
      expect(posts, hasLength(1));
      final body = server.bodyOf(posts.single);
      expect(body['deviceId'], await identity.deviceId());
      expect(body['name'], 'Till');
      expect(body['model'], 'android');
    });

    test('an unreachable server means "try again later"', () async {
      final identity = DeviceIdentity(store.meta);
      server.offline = true;
      expect(await identity.ensureRegistered(api(), baseUrl: 'http://a'),
          isFalse);

      server.offline = false;
      expect(await identity.ensureRegistered(api(), baseUrl: 'http://a'),
          isTrue);
      expect(server.posts('/sync/devices/register'), hasLength(1));
    });

    test('a server refusal does not mark the till registered', () async {
      final identity = DeviceIdentity(store.meta);
      server.deviceRegisterError = 'Sync is not available';
      expect(await identity.ensureRegistered(api(), baseUrl: 'http://a'),
          isFalse);

      server.deviceRegisterError = null;
      expect(await identity.ensureRegistered(api(), baseUrl: 'http://a'),
          isTrue);
    });

    test('a new base URL registers again with the same id', () async {
      final identity = DeviceIdentity(store.meta);
      await identity.ensureRegistered(api(), baseUrl: 'http://a');
      await identity.ensureRegistered(api(), baseUrl: 'http://b');

      final posts = server.posts('/sync/devices/register').toList();
      expect(posts, hasLength(2));
      expect(
        server.bodyOf(posts.first)['deviceId'],
        server.bodyOf(posts.last)['deviceId'],
      );
    });
  });

  group('Session device registration', () {
    test('signing in registers the till in the background, once', () async {
      final session = Session(
        tokenStore: MemoryTokenStore(),
        httpClient: server.client,
        localStore: store,
      );
      await session.signIn(username: 'tester', password: 'secret');
      await session.deviceRegistration;

      final posts = server.posts('/sync/devices/register').toList();
      expect(posts, hasLength(1));
      final body = server.bodyOf(posts.single);
      expect(body['deviceId'], startsWith('KT-'));
      expect(body['name'], 'Kantemba till');
      expect(body['appVersion'], kAppVersion);

      await session.signOut();
      await session.signIn(username: 'tester', password: 'secret');
      await session.deviceRegistration;
      expect(server.posts('/sync/devices/register'), hasLength(1));
    });

    test('without a local store, sign-in works and nothing registers',
        () async {
      final session = await server.signedInSession();
      expect(session.isSignedIn, isTrue);
      expect(session.deviceRegistration, isNull);
      expect(server.posts('/sync/devices/register'), isEmpty);
    });
  });
}
