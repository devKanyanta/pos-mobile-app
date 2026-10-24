import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import '../data/models/sale_models.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Product> _products = const [];
  List<PaymentMethod> _methods = const [];
  final Map<int, int> _cart = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = SessionScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        session.pos.listProducts(),
        session.pos.listPaymentMethods(),
      ]);
      setState(() {
        _products = results[0] as List<Product>;
        _methods = results[1] as List<PaymentMethod>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total {
    var sum = 0.0;
    for (final entry in _cart.entries) {
      final product = _products.firstWhere((p) => p.id == entry.key);
      sum += product.price * (1 + product.vatRate / 100) * entry.value;
    }
    return sum;
  }

  void _change(Product p, int delta) {
    setState(() {
      final next = (_cart[p.id] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = next;
      }
    });
  }

  Future<void> _checkout() async {
    final sales = SessionScope.of(context).sales;
    final method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Choose payment method')),
            for (final m in _methods.where((m) => m.isActive))
              ListTile(
                title: Text(m.name),
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;

    final amount = _total;
    try {
      final sale = await sales.createSale(
        items: [
          for (final e in _cart.entries)
            SaleItemInput(productId: e.key, quantity: e.value),
        ],
        payments: [PaymentInput(paymentMethodId: method.id, amount: amount)],
        clientSaleId: DateTime.now().microsecondsSinceEpoch.toString(),
      );
      if (!mounted) return;
      setState(_cart.clear);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sale ${sale.saleNumber} completed')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _products.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
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
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : ListView(
              children: [
                for (final p in _products.where((p) => p.active))
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(
                        '${p.price.toStringAsFixed(2)} + VAT ${p.vatRate.toStringAsFixed(0)}%'
                        '${p.trackInventory ? ' · stock ${p.stockQuantity}' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: (_cart[p.id] ?? 0) > 0 ? () => _change(p, -1) : null,
                        ),
                        Text('${_cart[p.id] ?? 0}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _change(p, 1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _checkout,
                  child: Text('Pay ${_total.toStringAsFixed(2)}'),
                ),
              ),
            ),
    );
  }
}

/// Recent sales with void (unpaid or same-day) and full refund actions.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Sale> _sales = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await SessionScope.of(context).sales.listSales();
      if (mounted) setState(() => _sales = sales);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _void(Sale sale) async {
    final ok = await _confirm('Void sale ${sale.saleNumber}?');
    if (!ok || !mounted) return;
    await _run(() => SessionScope.of(context).sales.voidSale(sale.id));
  }

  Future<void> _refund(Sale sale) async {
    final ok = await _confirm('Fully refund sale ${sale.saleNumber}?');
    if (!ok || !mounted) return;
    await _run(() => SessionScope.of(context).sales.refund(
          sale.id,
          saleItemIds: [for (final i in sale.items) if (i.remainingQuantity > 0) i.id],
          reason: 'Full refund',
          zraReasonCode: null,
        ));
  }

  Future<bool> _confirm(String text) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _run(Future<Object?> Function() action) async {
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales history')),
      body: _loading && _sales.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    for (final s in _sales)
                      ListTile(
                        title: Text('${s.saleNumber} · ${s.totalAmount.toStringAsFixed(2)}'),
                        subtitle: Text('${s.saleStatus} · ${s.paymentStatus}'),
                        trailing: s.isVoided
                            ? null
                            : PopupMenuButton<String>(
                                onSelected: (v) =>
                                    v == 'void' ? _void(s) : _refund(s),
                                itemBuilder: (_) => [
                                  if (!s.isFullyPaid)
                                    const PopupMenuItem(value: 'void', child: Text('Void')),
                                  if (s.isFullyPaid && s.refundedAmount == 0)
                                    const PopupMenuItem(value: 'refund', child: Text('Refund')),
                                ],
                              ),
                      ),
                  ],
                ),
    );
  }
}
