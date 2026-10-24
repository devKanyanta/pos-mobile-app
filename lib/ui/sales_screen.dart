import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import '../data/models/sale_models.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/app_sheet.dart';
import 'widgets/busy_button.dart';
import 'widgets/notice_bar.dart';
import 'widgets/quantity_stepper.dart';
import 'widgets/state_views.dart';

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
  bool _paying = false;

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
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<Product>;
        _methods = results[1] as List<PaymentMethod>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
    if (_paying) return;
    final sales = SessionScope.of(context).sales;
    final messenger = ScaffoldMessenger.of(context);
    final method = await showAppSheet<PaymentMethod>(
      context,
      title: 'Choose payment method',
      subtitle: 'Total ${_total.toStringAsFixed(2)}',
      children: [
        for (final m in _methods.where((m) => m.isActive))
          SheetAction(
            icon: m.isCash
                ? Icons.payments_outlined
                : Icons.account_balance_wallet_outlined,
            title: m.name,
            onTap: () => Navigator.pop(context, m),
          ),
      ],
    );
    if (method == null || !mounted) return;

    final amount = _total;
    setState(() => _paying = true);
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
      NoticeBar.success(messenger, 'Sale ${sale.saleNumber} completed');
    } on ApiException catch (e) {
      NoticeBar.error(messenger, e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _products.isEmpty) {
      return const Scaffold(body: LoadingView());
    }
    final theme = Theme.of(context);
    final active = _products.where((p) => p.active).toList();
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
          ? StateView.error(message: _error!, onRetry: _load)
          : active.isEmpty
          ? const StateView(
              icon: Icons.inventory_2_outlined,
              title: 'No products to sell yet.',
            )
          : ListView.separated(
              itemCount: active.length,
              separatorBuilder: (_, _) =>
                  const Divider(indent: Gap.lg, endIndent: Gap.lg),
              itemBuilder: (context, i) {
                final p = active[i];
                return ListTile(
                  minTileHeight: 64,
                  title: Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${p.price.toStringAsFixed(2)} + VAT ${p.vatRate.toStringAsFixed(0)}%'
                    '${p.trackInventory ? ' · stock ${p.stockQuantity}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: QuantityStepper(
                    quantity: _cart[p.id] ?? 0,
                    onDecrement: (_cart[p.id] ?? 0) > 0 && !_paying
                        ? () => _change(p, -1)
                        : null,
                    onIncrement: _paying ? null : () => _change(p, 1),
                  ),
                );
              },
            ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: BusyButton(
                  label: _paying
                      ? 'Processing…'
                      : 'Pay ${_total.toStringAsFixed(2)}',
                  busy: _paying,
                  expand: true,
                  onPressed: _checkout,
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
  bool _working = false;

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
    final ok = await showConfirmDialog(
      context,
      icon: Icons.block,
      title: 'Void sale ${sale.saleNumber}?',
      message: 'The sale will be cancelled and its stock returned. This cannot be undone.',
      confirmLabel: 'Void sale',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => SessionScope.of(context).sales.voidSale(sale.id),
      done: 'Sale ${sale.saleNumber} voided.',
    );
  }

  Future<void> _refund(Sale sale) async {
    final ok = await showConfirmDialog(
      context,
      icon: Icons.undo,
      title: 'Fully refund sale ${sale.saleNumber}?',
      message:
          '${sale.totalAmount.toStringAsFixed(2)} will be refunded in full. '
          'This cannot be undone.',
      confirmLabel: 'Refund',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => SessionScope.of(context).sales.refund(
        sale.id,
        saleItemIds: [
          for (final i in sale.items)
            if (i.remainingQuantity > 0) i.id,
        ],
        reason: 'Full refund',
        zraReasonCode: null,
      ),
      done: 'Sale ${sale.saleNumber} refunded.',
    );
  }

  Future<void> _run(
    Future<Object?> Function() action, {
    required String done,
  }) async {
    if (_working) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      await action();
      NoticeBar.success(messenger, done);
      if (mounted) await _load();
    } on ApiException catch (e) {
      NoticeBar.error(messenger, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales history'),
        bottom: _working
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _loading && _sales.isEmpty
          ? const LoadingView()
          : _error != null
          ? StateView.error(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: _sales.isEmpty
                  ? const StateView(
                      icon: Icons.receipt_long_outlined,
                      title: 'No sales yet',
                      message: 'Completed sales will appear here.',
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(Gap.lg),
                      itemCount: _sales.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Gap.sm),
                      itemBuilder: (context, i) => _saleCard(_sales[i]),
                    ),
            ),
    );
  }

  Widget _saleCard(Sale s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canVoid = !s.isFullyPaid;
    final canRefund = s.isFullyPaid && s.refundedAmount == 0;
    final when = s.soldAt?.toLocal().toString().split('.').first;
    final (statusLabel, statusBackground, statusForeground) = s.isVoided
        ? ('Voided', scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : s.refundedAmount > 0
        ? ('Refunded', scheme.tertiaryContainer, scheme.onTertiaryContainer)
        : s.isFullyPaid
        ? ('Paid', scheme.primaryContainer, scheme.onPrimaryContainer)
        : ('Unpaid', scheme.errorContainer, scheme.onErrorContainer);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.saleNumber} · ${s.totalAmount.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: statusBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.sm,
                            vertical: 2,
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusForeground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '${s.saleStatus} · ${s.paymentStatus}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (when != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        when,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!s.isVoided && (canVoid || canRefund))
              PopupMenuButton<String>(
                tooltip: 'Sale actions',
                enabled: !_working,
                onSelected: (v) => v == 'void' ? _void(s) : _refund(s),
                itemBuilder: (_) => [
                  if (canVoid)
                    PopupMenuItem(
                      value: 'void',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.block, color: scheme.error),
                        title: const Text('Void'),
                      ),
                    ),
                  if (canRefund)
                    PopupMenuItem(
                      value: 'refund',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.undo, color: scheme.error),
                        title: const Text('Refund'),
                      ),
                    ),
                ],
              )
            else
              const SizedBox(width: Gap.md),
          ],
        ),
      ),
    );
  }
}
