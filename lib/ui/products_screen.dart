import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/scanning/barcode_normalizer.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import 'product_actions.dart';
import 'inventory_history_screen.dart';
import 'product_form_screen.dart';
import 'scan_barcode_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/app_sheet.dart';
import 'widgets/notice_bar.dart';
import 'widgets/state_views.dart';

enum _ProductFilter {
  all('All'),
  active('Active'),
  inactive('Inactive'),
  lowStock('Low stock');

  const _ProductFilter(this.label);
  final String label;
}

enum _ProductSort {
  name('name'),
  stockLow('stock ↑'),
  stockHigh('stock ↓'),
  priceHigh('price ↓');

  const _ProductSort(this.label);
  final String label;
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = const [];
  String? _error;
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  _ProductFilter _filter = _ProductFilter.all;
  _ProductSort _sort = _ProductSort.name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await SessionScope.of(context).pos.listProducts();
      if (mounted) setState(() => _products = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Product? product, String? barcode}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProductFormScreen(product: product, initialBarcode: barcode),
      ),
    );
    if (saved == true) await _load();
  }

  /// Scan to find a product: edit or add stock when it exists, offer to
  /// register it when it does not.
  Future<void> _scanToFind() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanBarcodeScreen(title: 'Find product'),
      ),
    );
    if (code == null || !mounted) return;

    final session = SessionScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final product = await session.pos.findByBarcode(code);
      if (!mounted) return;
      if (product == null) {
        await _offerToCreate(code, session.canManageProducts);
      } else {
        await _productSheet(product, session.canManageProducts);
      }
    } on ApiException catch (e) {
      NoticeBar.error(messenger, e.message);
    }
  }

  Future<void> _offerToCreate(String code, bool canManage) async {
    if (!canManage) {
      NoticeBar.info(
        ScaffoldMessenger.of(context),
        'No product has barcode $code.',
      );
      return;
    }
    final create = await showConfirmDialog(
      context,
      icon: Icons.qr_code_2,
      title: 'New barcode',
      message: 'No product has barcode $code. Register one now?',
      confirmLabel: 'Register',
      cancelLabel: 'Not now',
    );
    if (create && mounted) await _openForm(barcode: code);
  }

  Future<void> _productSheet(Product product, bool canManage) async {
    await showAppSheet<void>(
      context,
      title: product.name,
      subtitle:
          '${product.price.toStringAsFixed(2)} ex VAT · '
          'stock ${product.trackInventory ? product.stockQuantity : 'n/a'}'
          '${product.active ? '' : ' · inactive'}',
      children: [
        if (canManage && product.trackInventory)
          SheetAction(
            icon: Icons.add_box_outlined,
            title: 'Add stock',
            onTap: () async {
              Navigator.pop(context);
              if (await showRestockDialog(context, product)) await _load();
            },
          ),
        if (canManage && product.trackInventory)
          SheetAction(
            icon: Icons.tune,
            title: 'Adjust stock',
            onTap: () async {
              Navigator.pop(context);
              if (await showAdjustmentDialog(context, product)) await _load();
            },
          ),
        SheetAction(
          icon: Icons.history,
          title: 'Stock history',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventoryHistoryScreen(product: product),
              ),
            );
          },
        ),
        if (canManage)
          SheetAction(
            icon: Icons.edit_outlined,
            title: 'Edit product',
            onTap: () {
              Navigator.pop(context);
              _openForm(product: product);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = SessionScope.of(context).canManageProducts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            tooltip: 'Stock history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InventoryHistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Scan a barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanToFind,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading && _products.isEmpty
          ? const LoadingView()
          : _error != null
          ? StateView.error(message: _error!, onRetry: _load)
          : _buildList(canManage),
    );
  }

  Widget _buildList(bool canManage) {
    final visible = _visibleProducts();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xs),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search name, SKU or barcode',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.xs,
          ),
          child: Row(
            children: [
              for (final f in _ProductFilter.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
              const SizedBox(width: Gap.xs),
              PopupMenuButton<_ProductSort>(
                tooltip: 'Sort products',
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  for (final s in _ProductSort.values)
                    PopupMenuItem(value: s, child: Text('Sort: ${s.label}')),
                ],
                child: Chip(
                  avatar: const Icon(Icons.sort, size: 18),
                  label: Text('Sort: ${_sort.label}'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: visible.isEmpty
                ? StateView(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products match.',
                    message: _products.isEmpty
                        ? (canManage
                              ? 'Tap + to add your first product.'
                              : null)
                        : 'Try a different search or filter.',
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const Divider(indent: Gap.lg, endIndent: Gap.lg),
                    itemBuilder: (context, i) =>
                        _productTile(visible[i], canManage),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _productTile(Product p, bool canManage) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 64,
      title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(_subtitle(p)),
      trailing: p.lowStock || !p.active
          ? Chip(
              label: Text(p.active ? 'Low stock' : 'Inactive'),
              visualDensity: VisualDensity.compact,
              backgroundColor: p.active
                  ? scheme.errorContainer
                  : scheme.surfaceContainerHighest,
              labelStyle: TextStyle(
                fontSize: 12,
                color: p.active
                    ? scheme.onErrorContainer
                    : scheme.onSurfaceVariant,
              ),
              side: BorderSide.none,
            )
          : const Icon(Icons.chevron_right),
      onTap: () => _productSheet(p, canManage),
    );
  }

  List<Product> _visibleProducts() {
    final q = _query.trim().toLowerCase();
    final items = _products.where((p) {
      if (_filter == _ProductFilter.active && !p.active) return false;
      if (_filter == _ProductFilter.inactive && p.active) return false;
      if (_filter == _ProductFilter.lowStock && !p.lowStock) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q) ||
          (p.barcode ?? '').toLowerCase().contains(q);
    }).toList();
    items.sort(
      (a, b) => switch (_sort) {
        _ProductSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _ProductSort.stockLow => a.stockQuantity.compareTo(b.stockQuantity),
        _ProductSort.stockHigh => b.stockQuantity.compareTo(a.stockQuantity),
        _ProductSort.priceHigh => b.price.compareTo(a.price),
      },
    );
    return items;
  }

  String _subtitle(Product p) {
    final stock = p.trackInventory ? p.stockQuantity : 'n/a';
    final code = BarcodeNormalizer.canonical(p.barcode);
    return '${p.price.toStringAsFixed(2)} · stock $stock${code != null ? ' · $code' : ''}';
  }
}
