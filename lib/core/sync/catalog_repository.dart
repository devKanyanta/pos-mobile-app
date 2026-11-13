import '../../data/local/catalog_cache.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/pos_api.dart';
import '../api/api_exception.dart';
import '../checkout/product_lookup.dart';

/// What checkout reads products and payment methods through.
///
/// The server is asked first, so prices and stock are always the live ones
/// while the till is online; each answer also refreshes the local copy. When
/// the server cannot be reached the same question is answered from the
/// cached catalogue, which is how scanning and selling keep working offline.
///
/// After a connection failure the server is left alone for [offlineHold], so
/// a run of scans on a dead connection does not wait out a network timeout
/// each time; the first lookup after the hold goes to the server again.
/// Only connection failures fall back — a server that answers with an error
/// is believed. With nothing cached yet the original error is rethrown,
/// because an empty cache would wrongly report every barcode as unknown.
class CatalogRepository implements ProductLookup {
  CatalogRepository({
    required this._pos,
    required this._cache,
    this.offlineHold = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PosApi _pos;
  final CatalogCache _cache;
  final Duration offlineHold;
  final DateTime Function() _clock;

  DateTime? _heldUntil;

  /// True while lookups skip the server because it was just unreachable.
  bool get isOffline {
    final until = _heldUntil;
    return until != null && _clock().isBefore(until);
  }

  @override
  Future<Product?> findByBarcode(String barcode) => _remoteOrCache(
    () async {
      final product = await _pos.findByBarcode(barcode);
      if (product != null) await _remember([product]);
      return product;
    },
    () => _cache.productByBarcode(barcode),
  );

  /// Active payment methods are filtered by the caller; this returns all.
  Future<List<PaymentMethod>> paymentMethods() => _remoteOrCache(
    () async {
      final methods = await _pos.listPaymentMethods();
      await _guard(() => _cache.replacePaymentMethods(methods));
      return methods;
    },
    () async {
      final cached = await _cache.paymentMethods();
      return cached.isEmpty ? throw _NothingCached() : cached;
    },
  );

  /// The whole catalogue for name searches.
  Future<List<Product>> allProducts() => _remoteOrCache(
    () async {
      final products = await _pos.listProducts();
      await _remember(products);
      return products;
    },
    () => _cache.allProducts(),
  );

  Future<T> _remoteOrCache<T>(
    Future<T> Function() remote,
    Future<T> Function() cached,
  ) async {
    if (!isOffline) {
      try {
        final result = await remote();
        _heldUntil = null;
        return result;
      } on ApiException catch (e) {
        if (!e.isNetwork || await _cache.productCount() == 0) rethrow;
        _heldUntil = _clock().add(offlineHold);
      }
    }
    try {
      return await cached();
    } on _NothingCached {
      return remote();
    }
  }

  Future<void> _remember(List<Product> products) => _guard(
    () => _cache.applyProducts([
      for (final product in products) CatalogProduct.fromProduct(product),
    ]),
  );

  /// A cache write must never fail a lookup that the server answered.
  Future<void> _guard(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {}
  }
}

class _NothingCached implements Exception {}
