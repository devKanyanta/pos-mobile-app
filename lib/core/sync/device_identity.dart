import 'dart:math';

import '../../data/local/sync_meta.dart';
import '../../data/services/sync_api.dart';

/// The till's stable identity and its registration with the server.
///
/// The id is created once and kept in the local database, so the server sees
/// the same till across restarts, and queued offline sales keep their origin.
/// Registration runs again whenever the API base URL changes (a different
/// server knows nothing about this till) and is retried until it succeeds
/// once per server.
class DeviceIdentity {
  DeviceIdentity(this._meta);

  final SyncMeta _meta;

  /// This till's id, created on first use and stable afterwards.
  Future<String> deviceId() async {
    final existing = await _meta.get(SyncMeta.deviceIdKey);
    if (existing != null) return existing;
    final id = _newId();
    await _meta.set(SyncMeta.deviceIdKey, id);
    return id;
  }

  /// Makes sure this till is registered with the server at [baseUrl],
  /// registering it now if it is not. Returns false when the attempt failed
  /// (unreachable server, missing permission); calling again later retries.
  Future<bool> ensureRegistered(
    SyncApi api, {
    required String baseUrl,
    String? name,
    String? model,
    String? appVersion,
  }) async {
    if (await _meta.get(SyncMeta.deviceRegisteredUrlKey) == baseUrl) {
      return true;
    }
    final id = await deviceId();
    try {
      await api.registerDevice(
        deviceId: id,
        name: name,
        model: model,
        appVersion: appVersion,
      );
    } catch (_) {
      // Any failure means "not registered yet"; the next call tries again.
      return false;
    }
    await _meta.set(SyncMeta.deviceRegisteredUrlKey, baseUrl);
    return true;
  }

  static String _newId() {
    final random = Random.secure();
    final suffix = List.generate(
      4,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'KT-$time-$suffix'.toUpperCase();
  }
}
