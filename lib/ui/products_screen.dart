import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = const [];
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
      final items = await SessionScope.of(context).pos.listProducts();
      if (mounted) setState(() => _products = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProduct() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _NewProductDialog(),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        child: const Icon(Icons.add),
      ),
      body: _loading && _products.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    for (final p in _products)
                      ListTile(
                        title: Text(p.name),
                        subtitle: Text(
                            '${p.price.toStringAsFixed(2)} · stock ${p.trackInventory ? p.stockQuantity : 'n/a'}'),
                        trailing: p.lowStock
                            ? const Chip(label: Text('Low stock'))
                            : null,
                      ),
                  ],
                ),
    );
  }
}

class _NewProductDialog extends StatefulWidget {
  const _NewProductDialog();

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _vat = TextEditingController(text: '16');
  final _stock = TextEditingController(text: '0');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _vat.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text);
    final vat = double.tryParse(_vat.text);
    final stock = int.tryParse(_stock.text);
    if (_name.text.trim().isEmpty || price == null || vat == null || stock == null) {
      setState(() => _error = 'Enter a name, price, VAT rate and stock.');
      return;
    }
    try {
      await SessionScope.of(context).pos.createProduct({
        'name': _name.text.trim(),
        'price': price,
        'vatRate': vat,
        'stockQuantity': stock,
        'trackInventory': true,
        'active': true,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: _price,
              decoration: const InputDecoration(labelText: 'Price (ex VAT)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: _vat,
              decoration: const InputDecoration(labelText: 'VAT rate %'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: _stock,
              decoration: const InputDecoration(labelText: 'Stock'),
              keyboardType: TextInputType.number,
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
