import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import '../data/models/report_models.dart';
import 'theme/app_theme.dart';
import 'widgets/state_views.dart';

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
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading && today == null
          ? const LoadingView()
          : _error != null
          ? StateView.error(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Gap.lg),
                children: [
                  _section('Today (${today?.date ?? ''})', [
                    _metric('Sales', '${today?.salesCount ?? 0}'),
                    _metric(
                      'Total',
                      (today?.totalSales ?? 0).toStringAsFixed(2),
                      emphasize: true,
                    ),
                  ]),
                  const SizedBox(height: Gap.xl),
                  _section('Z-report', [
                    _metric('Received', '${totals['received'] ?? 0}'),
                    _metric('Refunded', '${totals['refunded'] ?? 0}'),
                    _metric('Expected', '${totals['expected'] ?? 0}'),
                    _metric('Declared', '${totals['declared'] ?? 0}'),
                    _metric(
                      'Variance',
                      '${totals['variance'] ?? 0}',
                      emphasize: true,
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm, left: Gap.xs),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(indent: Gap.lg, endIndent: Gap.lg),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, {bool emphasize = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style:
                (emphasize
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyLarge)
                    ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
