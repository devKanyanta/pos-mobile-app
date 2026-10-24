import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/catalog_models.dart';
import 'widgets/app_dialog.dart';
import 'widgets/notice_bar.dart';
import 'widgets/status_banner.dart';

/// Asks for a quantity and receives that stock for [product]
/// (`POST /inventory-movements/restock`). Returns true if stock was added.
///
/// The dialog stays open while the request runs and shows a server rejection
/// inline with the entered quantity kept, so nothing is lost on a failure.
Future<bool> showRestockDialog(BuildContext context, Product product) async {
  final messenger = ScaffoldMessenger.of(context);

  final quantity = await showDialog<int>(
    context: context,
    builder: (_) => _RestockDialog(product: product),
  );
  if (quantity == null) return false;

  NoticeBar.success(messenger, 'Added $quantity to ${product.name}.');
  return true;
}

/// Records a signed stock correction with a required reason
/// (`POST /inventory-movements/adjustment`). Returns true once the server has saved it.
Future<bool> showAdjustmentDialog(BuildContext context, Product product) async {
  final messenger = ScaffoldMessenger.of(context);

  final entry = await showDialog<({int quantity, String reason})>(
    context: context,
    builder: (_) => _AdjustmentDialog(product: product),
  );
  if (entry == null) return false;

  NoticeBar.success(
    messenger,
    'Adjusted ${product.name} by ${entry.quantity > 0 ? '+' : ''}${entry.quantity}.',
  );
  return true;
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({required this.product});

  final Product product;

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  String? _quantityError;
  String? _reasonError;
  String? _serverError;
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// The stock level after this change, or null while the entry is not a number.
  int? get _resulting {
    final change = int.tryParse(_quantity.text.trim());
    return change == null ? null : widget.product.stockQuantity + change;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final value = int.tryParse(_quantity.text.trim());
    final reason = _reason.text.trim();
    final stock = widget.product.stockQuantity;

    String? quantityError;
    String? reasonError;
    if (value == null || value == 0) {
      quantityError =
          'Enter a whole number, positive or negative, that is not zero.';
    } else if (stock + value < 0) {
      quantityError = 'Stock cannot go below zero (currently $stock).';
    }
    if (reason.isEmpty) reasonError = 'Enter a reason for the adjustment.';
    if (quantityError != null || reasonError != null) {
      setState(() {
        _quantityError = quantityError;
        _reasonError = reasonError;
        _serverError = null;
      });
      return;
    }

    setState(() {
      _quantityError = null;
      _reasonError = null;
      _serverError = null;
      _busy = true;
    });
    try {
      await SessionScope.of(context).pos
          .adjustStock(widget.product.id, value!, reason);
      if (mounted) Navigator.pop(context, (quantity: value, reason: reason));
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resulting = _resulting;
    return AppDialog(
      title: 'Adjust stock',
      description:
          '${widget.product.name} · currently ${widget.product.stockQuantity} in stock',
      primaryLabel: _busy ? 'Saving…' : 'Save adjustment',
      busy: _busy,
      onPrimary: _submit,
      children: [
        TextField(
          controller: _quantity,
          enabled: !_busy,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
          ],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Change (use - to reduce)',
            helperText: resulting == null
                ? null
                : 'New stock level: $resulting',
            errorText: _quantityError,
          ),
          onChanged: (_) => setState(() => _quantityError = null),
        ),
        TextField(
          controller: _reason,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. Damaged, stock count correction',
            errorText: _reasonError,
          ),
          onChanged: (_) => setState(() => _reasonError = null),
          onSubmitted: (_) => _submit(),
        ),
        if (_serverError != null) StatusBanner.error(_serverError!),
      ],
    );
  }
}

/// Owns its text controller so it outlives the dialog's closing animation.
class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.product});

  final Product product;

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  String? _serverError;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() {
        _error = 'Enter a whole number above zero.';
        _serverError = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _serverError = null;
      _busy = true;
    });
    try {
      await SessionScope.of(context).pos.restockProduct(
        widget.product.id,
        value,
        notes: 'Added from barcode scan',
      );
      if (mounted) Navigator.pop(context, value);
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Add stock: ${widget.product.name}',
      description: 'Currently ${widget.product.stockQuantity} in stock',
      primaryLabel: _busy ? 'Adding…' : 'Add',
      busy: _busy,
      onPrimary: _submit,
      children: [
        TextField(
          controller: _controller,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Units received',
            prefixIcon: const Icon(Icons.add_box_outlined),
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        if (_serverError != null) StatusBanner.error(_serverError!),
      ],
    );
  }
}
