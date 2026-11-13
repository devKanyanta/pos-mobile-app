import '../../data/local/catalog_cache.dart';
import '../../data/local/sale_queue.dart';
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
///
/// Stock levels have the units of sales still waiting in the upload [queue]
/// taken off, whichever way they were answered: the server will deduct them
/// when those sales arrive, so they are already gone from the shelf and the
/// till must not sell them a second time.
class CatalogRepository implements ProductLookup {
  CatalogRepository({
    required this._pos,
    required this._cache,
    this.queue,
    this.offlineHold = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PosApi _pos;
  final CatalogCache _cache;
  final SaleQueue? queue;
  final Duration offlineHold;
  final DateTime Function() _clock;

  DateTime? _heldUntil;
  bool _noNetwork = false;

  /// True while lookups skip the server: it was just unreachable, or the
  /// phone reports no network at all.
  bool get isOffline {
    if (_noNetwork) return true;
    final until = _heldUntil;
    return until != null && _clock().isBefore(until);
  }

  /// The phone's own view of the network. Losing it entirely means the
  /// server cannot be reached, so lookups go to the cache at once; getting a
  /// network back lifts any hold so the next lookup asks the server again.
  void setNetworkAvailable(bool available) {
    _noNetwork = !available;
    if (available) _heldUntil = null;
  }

  @override
  Future<Product?> findByBarcode(String barcode) async {
    final product = await _remoteOrCache(
      () async {
        final product = await _pos.findByBarcode(barcode);
        if (product != null) await _remember([product]);
        return product;
      },
      () => _cache.productByBarcode(barcode),
    );
    if (product == null) return null;
    return (await _withoutQueued([product])).single;
  }

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
  Future<List<Product>> allProducts() async => _withoutQueued(
    await _remoteOrCache(() async {
      final products = await _pos.listProducts();
      await _remember(products);
      return products;
    }, () => _cache.allProducts()),
  );

  Future<List<Product>> _withoutQueued(List<Product> products) async {
    final queued = await queue?.pendingQuantities() ?? const <int, int>{};
    if (queued.isEmpty) return products;
    return [
      for (final product in products)
        if (product.trackInventory && queued.containsKey(product.id))
          product.withStock(
            (product.stockQuantity - queued[product.id]!).clamp(0, 1 << 31),
          )
        else
          product,
    ];
  }

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
