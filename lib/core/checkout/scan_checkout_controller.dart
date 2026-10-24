import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../data/models/catalog_models.dart';
import '../api/api_exception.dart';
import '../scanning/barcode_normalizer.dart';
import '../scanning/scan_deduplicator.dart';
import 'cart.dart';
import 'product_lookup.dart';

/// What happened to a scanned or typed barcode.
enum ScanOutcome { added, unknown, inactive, outOfStock, invalid, failed }

/// A message for the cashier about the most recent scan.
class ScanFeedback {
  const ScanFeedback(this.outcome, this.message, {this.product});

  final ScanOutcome outcome;
  final String message;
  final Product? product;

  bool get isError => outcome != ScanOutcome.added;
}

/// Turns barcode detections into cart changes.
///
/// UI-free on purpose: the camera widget only forwards raw strings to
/// [onDetected]; everything else (duplicate suppression, backend lookup,
/// stock rules, ordering) lives here so it can be tested without a camera.
///
/// * Camera frames repeat the same code many times, so [onDetected] filters
///   them with a [ScanDeduplicator]; a deliberate re-scan adds another unit.
/// * Lookups run strictly one at a time, in the order scanned, so quick
///   successive scans of different products are never dropped or reordered.
/// * Product data always comes from the backend lookup, never from the device.
class ScanCheckoutController extends ChangeNotifier {
  ScanCheckoutController({
    required this.lookup,
    Cart? cart,
    ScanDeduplicator? deduplicator,
    DateTime Function()? clock,
  }) : cart = cart ?? Cart(),
       _dedupe = deduplicator ?? ScanDeduplicator(),
       _clock = clock ?? DateTime.now;

  final ProductLookup lookup;
  final ScanDeduplicator _dedupe;
  final DateTime Function() _clock;
  final Cart cart;

  final Queue<_Pending> _queue = Queue();
  bool _draining = false;
  bool _disposed = false;
  ScanFeedback? _feedback;

  ScanFeedback? get feedback => _feedback;

  /// True while a lookup is in flight or waiting.
  bool get busy => _draining;

  /// A detection from the camera. Repeats of the same code are ignored.
  void onDetected(String raw) {
    final code = BarcodeNormalizer.canonical(raw);
    if (code == null) return;
    if (!_dedupe.accept(code, _clock())) return;
    _enqueue(code);
  }

  /// A barcode typed by the cashier. Always processed (no duplicate filter),
  /// and completes with the result.
  Future<ScanFeedback> addByBarcode(String raw) {
    final code = BarcodeNormalizer.canonical(raw);
    if (code == null) {
      return Future.value(
        _publish(const ScanFeedback(ScanOutcome.invalid, 'Enter a barcode.')),
      );
    }
    return _enqueue(code);
  }

  /// Shows a message from outside the scan flow (e.g. a failed name search).
  ScanFeedback report(ScanOutcome outcome, String message) =>
      _publish(ScanFeedback(outcome, message));

  /// Adds a product chosen from a search result, applying the same rules.
  ScanFeedback addProduct(Product product) => _publish(_tryAdd(product));

  /// Raises a line's quantity by one, within available stock.
  ScanFeedback increment(int productId) {
    final line = cart.lines.where((l) => l.product.id == productId).firstOrNull;
    if (line == null) {
      return _publish(
        const ScanFeedback(ScanOutcome.failed, 'Item is not in the sale.'),
      );
    }
    return _publish(_tryAdd(line.product));
  }

  void decrement(int productId) {
    cart.setQuantity(productId, cart.quantityOf(productId) - 1);
    _notify();
  }

  void remove(int productId) {
    cart.remove(productId);
    _notify();
  }

  void clear() {
    cart.clear();
    _dedupe.reset();
    _feedback = null;
    _notify();
  }

  void clearFeedback() {
    _feedback = null;
    _notify();
  }

  Future<ScanFeedback> _enqueue(String code) {
    final pending = _Pending(code);
    _queue.add(pending);
    unawaited(_drain());
    return pending.completer.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    _notify();
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final pending = _queue.removeFirst();
        pending.completer.complete(_publish(await _process(pending.code)));
      }
    } finally {
      _draining = false;
      // Anything left after dispose still needs an answer.
      while (_queue.isNotEmpty) {
        _queue.removeFirst().completer.complete(
          const ScanFeedback(ScanOutcome.failed, 'Scanner closed.'),
        );
      }
      _notify();
    }
  }

  Future<ScanFeedback> _process(String code) async {
    final problem = BarcodeNormalizer.validate(code);
    if (problem != null) {
      return ScanFeedback(
        ScanOutcome.invalid,
        'Unreadable barcode $code. $problem',
      );
    }
    try {
      final product = await lookup.findByBarcode(code);
      if (product == null) {
        return ScanFeedback(ScanOutcome.unknown, 'Unknown barcode $code');
      }
      return _tryAdd(product);
    } on ApiException catch (e) {
      final message = e.isNetwork
          ? 'No connection to the server. Check the network, then scan again.'
          : e.message;
      return ScanFeedback(ScanOutcome.failed, message);
    }
  }

  ScanFeedback _tryAdd(Product product) {
    if (!product.active) {
      return ScanFeedback(
        ScanOutcome.inactive,
        '${product.name} is not available for sale.',
        product: product,
      );
    }
    final inCart = cart.quantityOf(product.id);
    if (product.trackInventory && inCart + 1 > product.stockQuantity) {
      final message = product.stockQuantity <= 0
          ? '${product.name} is out of stock.'
          : 'Only ${product.stockQuantity} of ${product.name} in stock.';
      return ScanFeedback(ScanOutcome.outOfStock, message, product: product);
    }
    cart.add(product);
    return ScanFeedback(
      ScanOutcome.added,
      'Added ${product.name} (${inCart + 1})',
      product: product,
    );
  }

  ScanFeedback _publish(ScanFeedback feedback) {
    _feedback = feedback;
    _notify();
    return feedback;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _Pending {
  _Pending(this.code);

  final String code;
  final Completer<ScanFeedback> completer = Completer();
}
