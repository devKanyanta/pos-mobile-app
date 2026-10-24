import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/report_models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  TodaySummary? _today;
  Map<String, dynamic>? _zReport;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final reports = SessionScope.of(context).reports;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = await reports.today();
      final z = await reports.zReport();
      if (mounted) {
        setState(() {
          _today = today;
          _zReport = z;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final totals = (_zReport?['totals'] as Map?) ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading && today == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Today (${today?.date ?? ''})',
                        style: Theme.of(context).textTheme.titleMedium),
                    ListTile(
                      title: const Text('Sales'),
                      trailing: Text('${today?.salesCount ?? 0}'),
                    ),
                    ListTile(
                      title: const Text('Total'),
                      trailing: Text((today?.totalSales ?? 0).toStringAsFixed(2)),
                    ),
                    const Divider(),
                    Text('Z-report', style: Theme.of(context).textTheme.titleMedium),
                    ListTile(
                      title: const Text('Received'),
                      trailing: Text('${totals['received'] ?? 0}'),
                    ),
                    ListTile(
                      title: const Text('Refunded'),
                      trailing: Text('${totals['refunded'] ?? 0}'),
                    ),
                    ListTile(
                      title: const Text('Expected'),
                      trailing: Text('${totals['expected'] ?? 0}'),
                    ),
                    ListTile(
                      title: const Text('Declared'),
                      trailing: Text('${totals['declared'] ?? 0}'),
                    ),
                    ListTile(
                      title: const Text('Variance'),
                      trailing: Text('${totals['variance'] ?? 0}'),
                    ),
                  ],
                ),
    );
  }
}
