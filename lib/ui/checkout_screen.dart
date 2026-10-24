import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/api_exception.dart';
import '../core/checkout/checkout_service.dart';
import '../core/checkout/scan_checkout_controller.dart';
import '../core/scanning/barcode_normalizer.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import '../data/models/sale_models.dart';
import 'sales_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/app_sheet.dart';
import 'widgets/barcode_scanner_view.dart';
import 'widgets/busy_button.dart';
import 'widgets/quantity_stepper.dart';
import 'widgets/state_views.dart';
import 'widgets/status_banner.dart';

/// Barcode-first checkout: scan products, review the cart, pay.
///
/// Every scan is looked up on the server, so prices and stock are always the
/// backend's. Paying sends the items and the tender in one request and the
/// server calculates and records everything atomically.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, this.active = true});

  /// False while another tab is showing, so the camera is released.
  final bool active;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  ScanCheckoutController? _scan;
  CheckoutService? _checkout;
  final TextEditingController _manualController = TextEditingController();

  List<PaymentMethod> _methods = const [];
  List<Product>? _catalogue; // loaded lazily, only for name search
  String? _loadError;
  bool _loading = true;
  bool _paying = false;
  bool _coveredByPage = false;
  ScanFeedback? _lastHaptic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scan != null) return;
    final session = SessionScope.of(context);
    _scan = ScanCheckoutController(lookup: session.pos)
      ..addListener(_onScanChanged);
    _checkout = CheckoutService(session.sales);
    _loadMethods();
  }

  @override
  void dispose() {
    _scan?.removeListener(_onScanChanged);
    _scan?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onScanChanged() {
    final feedback = _scan!.feedback;
    if (feedback != null && !identical(feedback, _lastHaptic)) {
      _lastHaptic = feedback;
      if (feedback.isError) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadMethods() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final methods = await SessionScope.of(context).pos.listPaymentMethods();
      if (mounted) {
        setState(() => _methods = methods.where((m) => m.isActive).toList());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _scannerOn => widget.active && !_paying && !_coveredByPage;

  /// Manual fallback: a barcode first, then a name search.
  Future<void> _manualLookup() async {
    final scan = _scan!;
    final query = _manualController.text.trim();
    if (query.isEmpty) return;

    final canonical = BarcodeNormalizer.canonical(query);
    final looksLikeBarcode =
        !query.contains(' ') && BarcodeNormalizer.isValid(canonical);

    if (looksLikeBarcode) {
      final result = await scan.addByBarcode(query);
      if (!mounted) return;
      if (result.outcome != ScanOutcome.unknown &&
          result.outcome != ScanOutcome.invalid) {
        _manualController.clear();
        return;
      }
      // Digits only can only be a barcode, never a product name: stop here
      // (the banner already says the barcode is unknown) instead of downloading
      // the catalogue for a search that cannot succeed.
      if (RegExp(r'^\d+$').hasMatch(query)) return;
    }

    final catalogue = await _loadCatalogue();
    if (catalogue == null || !mounted) return;
    final matches = catalogue
        .where(
          (p) => p.active && p.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();

    if (matches.isEmpty) {
      // Keep "Unknown barcode ..." when the text was also tried as a barcode.
      if (!looksLikeBarcode) {
        scan.report(ScanOutcome.unknown, 'No product matches "$query"');
      }
    } else if (matches.length == 1) {
      scan.addProduct(matches.single);
      _manualController.clear();
    } else {
      final chosen = await _pickProduct(matches);
      if (chosen != null) {
        scan.addProduct(chosen);
        _manualController.clear();
      }
    }
  }

  Future<List<Product>?> _loadCatalogue() async {
    if (_catalogue != null) return _catalogue;
    try {
      final all = await SessionScope.of(context).pos.listProducts();
      _catalogue = all;
      return all;
    } on ApiException catch (e) {
      _scan?.report(ScanOutcome.failed, e.message);
      return null;
    }
  }

  Future<Product?> _pickProduct(List<Product> matches) {
    return showAppSheet<Product>(
      context,
      title: 'Choose a product',
      subtitle: '${matches.length} products match',
      children: [
        for (final p in matches.take(20))
          SheetAction(
            icon: Icons.inventory_2_outlined,
            title: p.name,
            subtitle: p.price.toStringAsFixed(2),
            onTap: () => Navigator.pop(context, p),
          ),
      ],
    );
  }

  Future<void> _openHistory() async {
    setState(() => _coveredByPage = true);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
    );
    if (mounted) setState(() => _coveredByPage = false);
  }

  Future<void> _pay() async {
    final scan = _scan!;
    if (_paying || scan.cart.isEmpty) return;

    if (_methods.isEmpty) {
      await _loadMethods();
      if (_methods.isEmpty || !mounted) return;
    }
    final method = await _chooseMethod();
    if (method == null || !mounted) return;

    String? reference;
    if (method.requiresReference) {
      reference = await _askText(
        title: '${method.name} confirmation code',
        label: 'Transaction reference',
      );
      if (reference == null || !mounted) return;
    }

    double? received;
    if (method.isCash) {
      final text = await _askText(
        title: 'Cash received',
        label: 'Amount received (leave empty for exact)',
        number: true,
        allowEmpty: true,
        helper:
            'Estimated total ${scan.cart.total.toStringAsFixed(2)}. '
            'The server confirms the final amount.',
      );
      if (text == null || !mounted) return;
      if (text.isNotEmpty) received = double.tryParse(text);
    }

    setState(() => _paying = true);
    try {
      final sale = await _checkout!.complete(
        scan.cart,
        method,
        reference: reference,
        amountReceived: received,
      );
      if (!mounted) return;
      scan.clear();
      // The sale is done: don't leave a spinner running behind the receipt.
      setState(() => _paying = false);
      await _showReceipt(sale);
    } on ApiException catch (e) {
      if (!mounted) return;
      // The cart and the pending sale id are kept, so retrying is safe.
      scan.report(
        ScanOutcome.failed,
        e.isNetwork
            ? 'Payment not confirmed: ${e.message} Tap Pay again; the sale will not be duplicated.'
            : 'Payment failed: ${e.message}',
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<PaymentMethod?> _chooseMethod() {
    return showAppSheet<PaymentMethod>(
      context,
      title: 'Choose payment method',
      subtitle: 'Total ${_scan!.cart.total.toStringAsFixed(2)}',
      children: [
        for (final m in _methods)
          SheetAction(
            icon: _methodIcon(m),
            title: m.name,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, m),
          ),
      ],
    );
  }

  static IconData _methodIcon(PaymentMethod m) {
    final name = m.name.toLowerCase();
    if (m.isCash) return Icons.payments_outlined;
    if (name.contains('card') ||
        name.contains('visa') ||
        name.contains('pos')) {
      return Icons.credit_card;
    }
    if (m.requiresReference ||
        name.contains('mobile') ||
        name.contains('mtn') ||
        name.contains('airtel') ||
        name.contains('money')) {
      return Icons.smartphone;
    }
    return Icons.account_balance_wallet_outlined;
  }

  /// Returns the entered text, or null if cancelled.
  Future<String?> _askText({
    required String title,
    required String label,
    bool number = false,
    bool allowEmpty = false,
    String? helper,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextPromptDialog(
        title: title,
        label: label,
        number: number,
        allowEmpty: allowEmpty,
        helper: helper,
      ),
    );
  }

  Future<void> _showReceipt(Sale sale) {
    final paid = sale.paymentStatus == 'PAID';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        icon: paid ? Icons.check_circle_outline : Icons.receipt_long_outlined,
        title: paid ? 'Sale complete' : 'Sale recorded',
        hideSecondary: true,
        primaryLabel: 'New sale',
        onPrimary: () => Navigator.pop(context),
        children: [
          Text(
            'Sale ${sale.saleNumber}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Total ${sale.totalAmount.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sale.changeGiven > 0)
            Text(
              'Change ${sale.changeGiven.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
              ),
            ),
          if (!paid)
            Text(
              'Balance due ${sale.balanceDue.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: scheme.error),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear this sale?',
      message: 'All items will be removed from the cart.',
      confirmLabel: 'Clear sale',
      destructive: true,
      icon: Icons.delete_sweep_outlined,
    );
    if (!ok || !mounted) return;
    _scan!.clear();
    _checkout!.reset();
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    if (scan == null || (_loading && _methods.isEmpty)) {
      return const Scaffold(body: LoadingView());
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        actions: [
          IconButton(
            tooltip: 'Sales history',
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Clear sale',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: scan.cart.isEmpty || _paying ? null : _confirmClear,
          ),
        ],
      ),
      // The scanner and messages share one area capped at 45% of the body: on a
      // small screen or at a large text size it scrolls inside that cap instead
      // of pushing the cart (or the page) out of bounds.
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.45,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // While the keyboard is up the user is typing, so the camera
                    // collapses until the keyboard closes.
                    if (MediaQuery.viewInsetsOf(context).bottom == 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Gap.lg,
                          Gap.sm,
                          Gap.lg,
                          0,
                        ),
                        child: BarcodeScannerView(
                          enabled: _scannerOn,
                          height: (MediaQuery.sizeOf(context).height * 0.24)
                              .clamp(120.0, 200.0),
                          onBarcode: scan.onDetected,
                        ),
                      ),
                    if (_loadError != null)
                      _banner(
                        '$_loadError',
                        kind: BannerKind.error,
                        retry: _loadMethods,
                      ),
                    if (scan.feedback != null)
                      _banner(
                        scan.feedback!.message,
                        kind: scan.feedback!.isError
                            ? BannerKind.error
                            : BannerKind.info,
                      ),
                  ],
                ),
              ),
            ),
            // Outside the scrolling area so typing a barcode is always one tap away.
            _manualField(),
            Expanded(child: _cartList(scan)),
          ],
        ),
      ),
      bottomNavigationBar: _summary(scan),
    );
  }

  Widget _banner(String text, {required BannerKind kind, VoidCallback? retry}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
      child: StatusBanner(
        text,
        kind: kind,
        actionLabel: retry == null ? null : 'Retry',
        onAction: retry,
      ),
    );
  }

  Widget _manualField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
      child: TextField(
        controller: _manualController,
        enabled: !_paying,
        decoration: InputDecoration(
          labelText: 'Barcode or product name',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Add',
            icon: const Icon(Icons.add),
            onPressed: _paying ? null : _manualLookup,
          ),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _manualLookup(),
      ),
    );
  }

  Widget _cartList(ScanCheckoutController scan) {
    final lines = scan.cart.lines;
    if (lines.isEmpty) {
      return const StateView(
        icon: Icons.shopping_cart_outlined,
        title: 'No items yet. Scan a product to start.',
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.lg),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
      itemBuilder: (context, i) {
        final line = lines[i];
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
                        line.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${line.unitTotal.toStringAsFixed(2)} each · '
                        'subtotal ${line.lineTotal.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                QuantityStepper(
                  quantity: line.quantity,
                  onDecrement: _paying
                      ? null
                      : () => scan.decrement(line.product.id),
                  onIncrement: _paying
                      ? null
                      : () => scan.increment(line.product.id),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: _paying
                      ? null
                      : () => scan.remove(line.product.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summary(ScanCheckoutController scan) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = scan.cart.lines.fold<int>(0, (sum, l) => sum + l.quantity);
    // At large text sizes a side-by-side total and button squeeze each other,
    // so the button moves below the total and spans the width.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final totals = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          items == 1 ? '1 item' : '$items items',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          'Total ${scan.cart.total.toStringAsFixed(2)}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final pay = BusyButton(
      label: _paying ? 'Processing…' : 'Pay',
      busy: _paying,
      expand: stacked,
      onPressed: scan.cart.isEmpty ? null : _pay,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    totals,
                    const SizedBox(height: Gap.md),
                    pay,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: totals),
                    const SizedBox(width: Gap.md),
                    pay,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A one-field prompt. It owns its controller so the controller outlives the
/// dialog's closing animation.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.number,
    required this.allowEmpty,
    this.helper,
  });

  final String title;
  final String label;
  final bool number;
  final bool allowEmpty;
  final String? helper;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && !widget.allowEmpty) {
      setState(() => _error = 'This field is required.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      primaryLabel: 'Continue',
      onPrimary: _submit,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: widget.number
              ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
              : null,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helper,
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}
