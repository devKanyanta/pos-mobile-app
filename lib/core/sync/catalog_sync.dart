import '../../data/local/catalog_cache.dart';
import '../../data/local/sync_meta.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/sync_api.dart';

/// Keeps the device's catalogue cache in step with the server.
///
/// The first pull is a full snapshot; later pulls send the previous
/// `serverTime` as `since` and receive only what changed. Every pull also
/// carries the complete list of product ids, which is how deletions reach the
/// device. The bookmark moves forward only after everything was applied, so a
/// pull that fails half way is simply repeated.
class CatalogSync {
  CatalogSync({
    required this._api,
    required this._cache,
    required this._meta,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncApi _api;
  final CatalogCache _cache;
  final SyncMeta _meta;
  final DateTime Function() _clock;

  Future<bool>? _running;

  /// Pulls and applies the catalogue. Returns true when the cache is now up
  /// to date, false when the pull failed (offline, refused, malformed); the
  /// old cache stays untouched and the next call tries again. A call made
  /// while a pull is running joins it instead of starting a second one.
  Future<bool> sync() => _running ??= _pull().whenComplete(() => _running = null);

  /// Forgets the bookmark so the next pull is a full snapshot (the API base
  /// URL changed, so the old bookmark belongs to another server).
  Future<void> reset() => _meta.remove(SyncMeta.catalogSinceKey);

  Future<bool> _pull() async {
    try {
      final since = await _meta.get(SyncMeta.catalogSinceKey);
      final snapshot = await _api.fetchCatalog(since: since);

      await _cache.applyProducts(snapshot.products);
      final ids = snapshot.productIds;
      if (ids != null) await _cache.removeProductsNotIn(ids);
      await _cache.replaceCategories(snapshot.categories);
      await _cache.replacePaymentMethods(snapshot.paymentMethods);

      if (snapshot.serverTime.isNotEmpty) {
        await _meta.set(SyncMeta.catalogSinceKey, snapshot.serverTime);
      }
      await _meta.set(
        SyncMeta.lastCatalogSyncKey,
        formatLocalDateTime(_clock()),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
