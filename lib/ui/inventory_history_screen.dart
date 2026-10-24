import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/business_models.dart';
import '../data/models/catalog_models.dart';
import 'widgets/state_views.dart';
import 'theme/app_theme.dart';

/// Server-recorded stock movements, optionally limited to one [product].
/// Rows are shown exactly as the backend returns them.
class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({super.key, this.product});

  final Product? product;

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  List<InventoryMovement> _movements = const [];
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
      final items = await SessionScope.of(context).pos
          .listMovements(productId: widget.product?.id);
      if (mounted) setState(() => _movements = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.product?.name ?? 'Stock history';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading && _movements.isEmpty
          ? const LoadingView()
          : _error != null
          ? StateView.error(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: _movements.isEmpty
                  ? const StateView(
                      icon: Icons.swap_vert,
                      title: 'No stock movements recorded yet.',
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _movements.length,
                      separatorBuilder: (_, _) =>
                          const Divider(indent: 72, endIndent: Gap.lg),
                      itemBuilder: (context, i) => _MovementTile(_movements[i]),
                    ),
            ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile(this.movement);

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final sign = m.quantity > 0 ? '+' : '';
    final when = m.createdAt?.toLocal().toString().split('.').first ?? '';
    final scheme = Theme.of(context).colorScheme;
    final incoming = m.quantity > 0;
    return ListTile(
      minTileHeight: 64,
      leading: CircleAvatar(
        backgroundColor: incoming
            ? scheme.primaryContainer
            : scheme.errorContainer,
        foregroundColor: incoming
            ? scheme.onPrimaryContainer
            : scheme.onErrorContainer,
        child: Icon(incoming ? Icons.south_west : Icons.north_east, size: 20),
      ),
      title: Text('${_label(m.movementType)} · ${m.productName}'),
      subtitle: Text(
        [
          when,
          if (m.performedBy != null) m.performedBy!,
          if (m.notes != null) m.notes!,
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      trailing: Text(
        '$sign${m.quantity}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: m.quantity < 0 ? scheme.error : scheme.primary,
        ),
      ),
    );
  }

  static String _label(String type) => switch (type) {
    'RESTOCK' => 'Received',
    'ADJUSTMENT' => 'Adjustment',
    'SALE' => 'Sale',
    _ => type.toLowerCase().replaceAll('_', ' '),
  };
}
