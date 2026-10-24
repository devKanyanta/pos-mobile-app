import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api/api_exception.dart';
import '../core/checkout/cart.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import '../data/models/sale_models.dart';
import 'sales_screen.dart';

/// Barcode-first checkout: scan products, review the cart, pay.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final Cart _cart = Cart();
  final ScanDeduplicator _dedupe = ScanDeduplicator();
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
  );
  final TextEditingController _manualController = TextEditingController();

  Map<String, Product> _byBarcode = const {};
  List<Product> _products = const [];
  List<PaymentMethod> _methods = const [];
  String? _loadError;
  bool _loading = true;
  bool _paying = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scanner.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = SessionScope.of(context);
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        session.pos.listProducts(),
        session.pos.listPaymentMethods(),
      ]);
      final products = results[0] as List<Product>;
      setState(() {
        _products = products.where((p) => p.active).toList();
        _byBarcode = {
          for (final p in _products)
            if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!: p,
        };
        _methods = (results[1] as List<PaymentMethod>)
            .where((m) => m.isActive)
            .toList();
      });
    } on ApiException catch (e) {
      setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setFeedback(String text, {bool error = false}) {
    setState(() {
      _feedback = text;
      _feedbackIsError = error;
    });
  }

  /// Adds a product to the cart and reports it to the cashier.
  void _addProduct(Product product) {
    setState(() => _cart.add(product));
    _setFeedback('Added ${product.name} (${_cart.quantityOf(product.id)})');
  }

  void _onDetect(BarcodeCapture capture) {
    if (_paying) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.isEmpty) continue;
      if (!_dedupe.accept(code, DateTime.now())) continue;
      final product = _byBarcode[code];
      if (product == null) {
        _setFeedback('Unknown barcode $code', error: true);
      } else {
        _addProduct(product);
      }
      return;
    }
  }

  /// Manual fallback: exact barcode first, then a name search.
  void _manualLookup() {
    final query = _manualController.text.trim();
    if (query.isEmpty) return;
    final exact = _byBarcode[query];
    if (exact != null) {
      _addProduct(exact);
      _manualController.clear();
      return;
    }
    final matches = _products
        .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    if (matches.length == 1) {
      _addProduct(matches.single);
      _manualController.clear();
    } else if (matches.isEmpty) {
      _setFeedback('No product matches "$query"', error: true);
    } else {
      _setFeedback('${matches.length} products match "$query"; refine it');
    }
  }

  /// Reuses one client sale id across retries of the same cart, so a
  /// network failure after the server saved the sale cannot double-charge.
  String? _pendingSaleId;
  String? _pendingSignature;

  Future<void> _pay() async {
    if (_paying || _cart.isEmpty) return;
    final method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Choose payment method')),
            for (final m in _methods)
              ListTile(
                title: Text(m.name),
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;

    final sales = SessionScope.of(context).sales;
    final items = [
      for (final line in _cart.lines)
        SaleItemInput(productId: line.product.id, quantity: line.quantity),
    ];
    final amount = _cart.total;
    // A new id is needed whenever the cart differs from the failed attempt.
    final signature = '${[for (final i in items) '${i.productId}x${i.quantity}'].join(',')}|$amount|${method.id}';
    if (_pendingSignature != signature || _pendingSaleId == null) {
      _pendingSaleId = DateTime.now().microsecondsSinceEpoch.toString();
      _pendingSignature = signature;
    }

    setState(() => _paying = true);
    try {
      final sale = await sales.createSale(
        items: items,
        payments: [PaymentInput(paymentMethodId: method.id, amount: amount)],
        clientSaleId: _pendingSaleId,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _pendingSaleId = null;
      });
      _setFeedback('Sale ${sale.saleNumber} completed');
      await _load();
    } on ApiException catch (e) {
      // Keep the cart and the pending id so the cashier can retry safely.
      if (mounted) _setFeedback('Payment failed: ${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _products.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(child: Text(_loadError!)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        actions: [
          IconButton(
            tooltip: 'Sales history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Clear sale',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _cart.isEmpty
                ? null
                : () => setState(() {
                      _cart.clear();
                      _pendingSaleId = null;
                    }),
          ),
        ],
      ),
      body: Column(
        children: [
          _scannerArea(),
          if (_feedback != null) _feedbackBanner(),
          _manualField(),
          Expanded(child: _cartList()),
        ],
      ),
      bottomNavigationBar: _summary(),
    );
  }

  Widget _scannerArea() {
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera permission denied. Use manual entry below.'
                      : 'Camera unavailable. Use manual entry below.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const IgnorePointer(
            child: Text(
              'Point the camera at a barcode',
              style: TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: _feedbackIsError ? scheme.errorContainer : scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(_feedback!),
    );
  }

  Widget _manualField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _manualController,
        decoration: InputDecoration(
          labelText: 'Barcode or product name',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.add),
            onPressed: _manualLookup,
          ),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _manualLookup(),
      ),
    );
  }

  Widget _cartList() {
    if (_cart.isEmpty) {
      return const Center(child: Text('No items yet. Scan a product to start.'));
    }
    return ListView(
      children: [
        for (final line in _cart.lines)
          ListTile(
            title: Text(line.product.name),
            subtitle: Text(
              '${line.unitTotal.toStringAsFixed(2)} each · '
              'subtotal ${line.lineTotal.toStringAsFixed(2)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() =>
                      _cart.setQuantity(line.product.id, line.quantity - 1)),
                ),
                Text('${line.quantity}'),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() =>
                      _cart.setQuantity(line.product.id, line.quantity + 1)),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      setState(() => _cart.remove(line.product.id)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summary() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Total ${_cart.total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            FilledButton(
              onPressed: _cart.isEmpty || _paying ? null : _pay,
              child: Text(_paying ? 'Processing…' : 'Pay'),
            ),
          ],
        ),
      ),
    );
  }
}
