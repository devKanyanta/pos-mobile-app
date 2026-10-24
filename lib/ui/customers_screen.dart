import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/business_models.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/notice_bar.dart';
import 'widgets/state_views.dart';
import 'widgets/status_banner.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _customers = const [];
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

  Future<void> _add() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _NewCustomerDialog(),
    );
    if (created == true) {
      if (mounted) {
        NoticeBar.success(ScaffoldMessenger.of(context), 'Customer added.');
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add customer',
        onPressed: _add,
        child: const Icon(Icons.person_add),
      ),
      body: _loading && _customers.isEmpty
          ? const LoadingView()
          : _error != null
          ? StateView.error(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: _customers.isEmpty
                  ? const StateView(
                      icon: Icons.people_outline,
                      title: 'No customers yet',
                      message: 'Tap the button to add your first customer.',
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _customers.length,
                      separatorBuilder: (_, _) =>
                          const Divider(indent: 72, endIndent: Gap.lg),
                      itemBuilder: (context, i) => _tile(_customers[i]),
                    ),
            ),
    );
  }

  Widget _tile(Customer c) {
    final scheme = Theme.of(context).colorScheme;
    final name = c.fullName.trim();
    final contact = c.phone ?? c.email ?? '';
    return ListTile(
      minTileHeight: 64,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: contact.isEmpty ? null : Text(contact),
    );
  }
}

class _NewCustomerDialog extends StatefulWidget {
  const _NewCustomerDialog();

  @override
  State<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends State<_NewCustomerDialog> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  String? _firstError;
  String? _serverError;
  bool _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_first.text.trim().isEmpty) {
      setState(() => _firstError = 'First name is required.');
      return;
    }
    setState(() {
      _firstError = null;
      _serverError = null;
      _busy = true;
    });
    try {
      await SessionScope.of(context).pos.createCustomer({
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      // The dialog stays open with everything typed so far, ready to retry.
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'New customer',
      primaryLabel: _busy ? 'Saving…' : 'Save',
      busy: _busy,
      onPrimary: _save,
      onSecondary: () => Navigator.pop(context, false),
      children: [
        TextField(
          controller: _first,
          enabled: !_busy,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'First name',
            errorText: _firstError,
          ),
          onChanged: (_) {
            if (_firstError != null) setState(() => _firstError = null);
          },
        ),
        TextField(
          controller: _last,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Last name'),
        ),
        TextField(
          controller: _phone,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Phone'),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        if (_serverError != null) StatusBanner.error(_serverError!),
      ],
    );
  }
}
