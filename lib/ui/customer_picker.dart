import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/business_models.dart';
import 'theme/app_theme.dart';
import 'widgets/app_sheet.dart';
import 'widgets/state_views.dart';
import 'widgets/status_banner.dart';

/// Lets the cashier attach a customer to the sale being rung up.
///
/// Returns null when the sheet is dismissed (nothing changes). A non-null
/// result carries the choice: a customer, or `customer: null` for a walk-in
/// sale with no customer attached.
Future<({Customer? customer})?> showCustomerPicker(BuildContext context) {
  return showAppSheet<({Customer? customer})>(
    context,
    title: 'Customer',
    subtitle: 'Attach a customer to this sale, or sell to a walk-in.',
    children: const [_CustomerList()],
  );
}

class _CustomerList extends StatefulWidget {
  const _CustomerList();

  @override
  State<_CustomerList> createState() => _CustomerListState();
}

class _CustomerListState extends State<_CustomerList> {
  List<Customer> _customers = const [];
  String _query = '';
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
      final items = await SessionScope.of(context).pos.listCustomers();
      if (mounted) setState(() => _customers = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = _customers.where((c) {
      if (!c.isActive) return false;
      if (q.isEmpty) return true;
      return c.fullName.toLowerCase().contains(q) ||
          (c.phone ?? '').toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.sm),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name or phone',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SheetAction(
          icon: Icons.person_outline,
          title: 'Walk-in customer',
          subtitle: 'No customer attached',
          onTap: () => Navigator.pop(context, (customer: null)),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(Gap.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: StatusBanner.error(
              _error!,
              actionLabel: 'Retry',
              onAction: _load,
            ),
          )
        else if (visible.isEmpty)
          const SizedBox(
            height: 160,
            child: StateView(
              icon: Icons.people_outline,
              title: 'No customers match.',
            ),
          )
        else
          for (final c in visible)
            SheetAction(
              icon: Icons.person,
              title: c.fullName,
              subtitle: (c.phone ?? c.email),
              onTap: () => Navigator.pop(context, (customer: c)),
            ),
      ],
    );
  }
}
