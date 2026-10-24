import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/api_exception.dart';
import '../core/catalog/barcode_assignment.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import 'product_actions.dart';
import 'scan_barcode_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/busy_button.dart';
import 'widgets/status_banner.dart';

/// Create or edit a product, with a barcode that can be scanned or typed.
///
/// A barcode is checked against the server before saving. If another product
/// already carries it, the form never creates a duplicate: it points the user
/// at that product, or lets them add stock to it instead.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.initialBarcode});

  /// The product being edited, or null to create one.
  final Product? product;

  /// A barcode to start with (e.g. just scanned and not yet in the catalogue).
  final String? initialBarcode;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _vat;
  late final TextEditingController _stock;
  bool _active = true;

  BarcodeCheck? _check;
  bool _checking = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _barcode = TextEditingController(
      text: p?.barcode ?? widget.initialBarcode ?? '',
    );
    _price = TextEditingController(text: p != null ? p.price.toString() : '');
    _vat = TextEditingController(text: p != null ? p.vatRate.toString() : '16');
    _stock = TextEditingController(text: '0');
    _active = p?.active ?? true;
    if (widget.initialBarcode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyBarcode());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _vat.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanBarcodeScreen()),
    );
    if (code == null || !mounted) return;
    _barcode.text = code;
    await _verifyBarcode();
  }

  /// Asks the server whether the typed barcode is free. Returns the result.
  Future<BarcodeCheck> _verifyBarcode() async {
    final checker = BarcodeAssignmentChecker(SessionScope.of(context).pos);
    setState(() => _checking = true);
    final result = await checker.check(
      _barcode.text,
      editingProductId: widget.product?.id,
    );
    if (!mounted) return result;
    setState(() {
      _check = result;
      _checking = false;
      if (result.code != null && result.code != _barcode.text) {
        _barcode.text = result.code!;
      }
    });
    return result;
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text);
    final vat = double.tryParse(_vat.text);
    final stock = int.tryParse(_stock.text);
    if (_name.text.trim().isEmpty ||
        price == null ||
        vat == null ||
        (!_editing && stock == null)) {
      setState(
        () => _error =
            'Enter a name, price, VAT rate${_editing ? '' : ' and stock'}.',
      );
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final check = await _verifyBarcode();
      if (!mounted) return;
      if (check.status == BarcodeStatus.invalid) {
        setState(() => _error = check.message);
        return;
      }
      if (check.status == BarcodeStatus.taken) {
        // Nothing is being saved while the user decides, so release the form.
        setState(() => _saving = false);
        await _handleDuplicate(check.owner!);
        return;
      }

      final pos = SessionScope.of(context).pos;
      final code = check.code;
      if (_editing) {
        final body = <String, dynamic>{
          'name': _name.text.trim(),
          'price': price,
          'vatRate': vat,
          'active': _active,
        };
        // An empty string clears the barcode; leave it out when unchanged.
        if ((code ?? '') != (widget.product!.barcode ?? '')) {
          body['barcode'] = code ?? '';
        }
        await pos.updateProduct(widget.product!.id, body);
      } else {
        await pos.createProduct({
          'name': _name.text.trim(),
          'price': price,
          'vatRate': vat,
          'stockQuantity': stock,
          'trackInventory': true,
          'active': true,
          'barcode': ?code,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      // Includes the race where someone else took the barcode after the check.
      if (mounted) {
        setState(() => _error = e.message);
        if (e.status == 409) _verifyBarcode();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The barcode belongs to another product: offer it instead of a duplicate.
  Future<void> _handleDuplicate(Product owner) async {
    final canManage = SessionScope.of(context).canManageProducts;
    final action = await showDialog<_DuplicateAction>(
      context: context,
      builder: (context) => AppDialog(
        icon: Icons.qr_code_2,
        title: 'Barcode already in use',
        description:
            '${owner.name} already has barcode ${owner.barcode}'
            '${owner.trackInventory ? ' (stock ${owner.stockQuantity})' : ''}.\n\n'
            'A barcode can belong to only one product.',
        secondaryLabel: 'Use another barcode',
        onSecondary: () => Navigator.pop(context, _DuplicateAction.change),
        extraActions: [
          if (canManage && owner.trackInventory)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _DuplicateAction.addStock),
              child: const Text('Add stock'),
            ),
        ],
        primaryLabel: canManage ? 'Open product' : null,
        onPrimary: () => Navigator.pop(context, _DuplicateAction.open),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case _DuplicateAction.open:
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => ProductFormScreen(product: owner)),
        );
        if (saved == true && mounted) Navigator.pop(context, true);
      case _DuplicateAction.addStock:
        final added = await showRestockDialog(context, owner);
        if (added && mounted) Navigator.pop(context, true);
      case _DuplicateAction.change:
        _barcode.clear();
        setState(() => _check = null);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'New product')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                _sectionTitle('Details'),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  controller: _barcode,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Barcode (optional)',
                    helperText: 'Scan it or type it. Leave empty if the product has none.',
                    errorText: _check?.blocksSaving == true
                        ? _check?.message
                        : null,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_checking) const InlineSpinner(),
                        IconButton(
                          tooltip: 'Scan barcode',
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: _saving ? null : _scan,
                        ),
                      ],
                    ),
                  ),
                  onChanged: (_) => setState(() => _check = null),
                  onEditingComplete: () {
                    _verifyBarcode();
                    FocusScope.of(context).nextFocus();
                  },
                ),
                _barcodeStatus(),
                const SizedBox(height: Gap.xl),
                _sectionTitle('Pricing'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _price,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Price (ex VAT)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _vat,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'VAT rate %',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        textInputAction: _editing
                            ? TextInputAction.done
                            : TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xl),
                if (!_editing) ...[
                  _sectionTitle('Stock'),
                  TextField(
                    controller: _stock,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Opening stock',
                      helperText: 'Units on the shelf right now.',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                  ),
                ] else
                  Card(
                    child: SwitchListTile(
                      title: const Text('Active (can be sold)'),
                      subtitle: Text(
                        _active ? 'Shown at checkout' : 'Hidden from checkout',
                        style: theme.textTheme.bodySmall,
                      ),
                      value: _active,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _active = v),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: Gap.lg),
                  StatusBanner.error(_error!),
                ],
              ],
            ),
          ),
          // Part of the body (not bottomNavigationBar) so it rises above the keyboard.
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.lg,
                  Gap.sm,
                  Gap.lg,
                  Gap.md,
                ),
                child: BusyButton(
                  label: _saving ? 'Saving…' : 'Save',
                  busy: _saving,
                  expand: true,
                  onPressed: _save,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _barcodeStatus() {
    final check = _check;
    if (check == null) return const SizedBox.shrink();
    switch (check.status) {
      case BarcodeStatus.available:
        return Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: StatusBanner(
            'Barcode ${check.code} is available.',
            kind: BannerKind.success,
          ),
        );
      case BarcodeStatus.unverified:
        return Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: StatusBanner(check.message ?? '', kind: BannerKind.warning),
        );
      case BarcodeStatus.taken:
        return Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: StatusBanner(
            'Barcode ${check.code} is already used by ${check.owner!.name}.',
            kind: BannerKind.warning,
            actionLabel: 'What now?',
            onAction: () => _handleDuplicate(check.owner!),
          ),
        );
      case BarcodeStatus.none:
      case BarcodeStatus.invalid:
        return const SizedBox.shrink();
    }
  }
}

enum _DuplicateAction { change, addStock, open }
