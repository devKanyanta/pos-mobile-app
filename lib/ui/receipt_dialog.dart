import 'package:flutter/material.dart';

import '../core/receipt/receipt_data.dart';
import '../core/receipt/receipt_output.dart';
import '../core/session/session_scope.dart';
import '../data/models/receipt_models.dart';
import '../data/models/sale_models.dart';
import 'theme/app_theme.dart';
import 'widgets/status_banner.dart';

/// Shows the receipt for [sale] in a large modal that can be printed or saved
/// as a PDF.
///
/// The sale's own amounts show immediately. The business details and the fiscal
/// (ZRA) details are fetched in the background and appear when they arrive; a
/// failure to load them never blocks the receipt.
///
/// [title] is the headline ("Sale complete" right after paying, "Receipt" when
/// reopening one) and [doneLabel] the label of the button that closes it.
Future<void> showReceiptDialog(
  BuildContext context,
  Sale sale, {
  String? title,
  String doneLabel = 'New sale',
  ReceiptOutput output = const ReceiptOutput(),
}) {
  final session = SessionScope.of(context);
  final paid = sale.paymentStatus == 'PAID';
  return showDialog<void>(
    context: context,
    builder: (context) => ReceiptDialog(
      initial: ReceiptData(sale: sale),
      // A sale saved offline has nothing on the server to fetch yet.
      load: sale.offline
          ? () => session.offlineReceipt(sale)
          : () => ReceiptData.load(session.pos, session.sales, sale),
      title:
          title ??
          (sale.offline
              ? 'Saved offline'
              : paid
              ? 'Sale complete'
              : 'Sale recorded'),
      doneLabel: doneLabel,
      output: output,
    ),
  );
}

class ReceiptDialog extends StatefulWidget {
  const ReceiptDialog({
    super.key,
    required this.initial,
    required this.load,
    required this.title,
    required this.doneLabel,
    required this.output,
  });

  final ReceiptData initial;

  /// Fetches the business and fiscal details for the receipt.
  final Future<ReceiptData> Function() load;
  final String title;
  final String doneLabel;
  final ReceiptOutput output;

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

enum _Job { print, save }

class _ReceiptDialogState extends State<ReceiptDialog> {
  late ReceiptData _data = widget.initial;
  late final Future<ReceiptData> _loading;
  bool _loaded = false;
  _Job? _job;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loading = widget
        .load()
        .then((full) {
          if (mounted) {
            setState(() {
              _data = full;
              _loaded = true;
            });
          }
          return full;
        })
        .catchError((_) {
          if (mounted) setState(() => _loaded = true);
          return widget.initial;
        });
  }

  /// Prints or saves what is shown, waiting for the details still loading so
  /// the document never lacks the business name or fiscal data by a race.
  Future<void> _run(_Job job) async {
    if (_job != null) return;
    setState(() {
      _job = job;
      _error = null;
    });
    try {
      final data = await _loading;
      switch (job) {
        case _Job.print:
          await widget.output.print(data);
        case _Job.save:
          await widget.output.savePdf(data);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not ${job == _Job.print ? 'print' : 'save'} the receipt: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _job = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sale = _data.sale;
    final paid = sale.paymentStatus == 'PAID';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Receipt',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close receipt',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: paid
                          ? scheme.primaryContainer
                          : scheme.tertiaryContainer,
                      foregroundColor: paid
                          ? scheme.onPrimaryContainer
                          : scheme.onTertiaryContainer,
                      child: Icon(
                        paid ? Icons.check : Icons.receipt_long_outlined,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Sale ${sale.saleNumber}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (sale.offline) ...[
                      const SizedBox(height: Gap.md),
                      const StatusBanner(
                        'No connection. This sale is saved on this device and '
                        'will be sent to the server, and to ZRA, when the '
                        'connection returns. Give the customer this receipt '
                        'as proof of sale.',
                        kind: BannerKind.warning,
                      ),
                    ],
                    const SizedBox(height: Gap.lg),
                    _paper(context),
                  ],
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    StatusBanner.error(_error!),
                    const SizedBox(height: Gap.md),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _outputButton(
                          job: _Job.print,
                          label: 'Print',
                          icon: Icons.print_outlined,
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: _outputButton(
                          job: _Job.save,
                          label: 'Save PDF',
                          icon: Icons.picture_as_pdf_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(widget.doneLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outputButton({
    required _Job job,
    required String label,
    required IconData icon,
  }) {
    final busy = _job == job;
    return OutlinedButton.icon(
      onPressed: _job == null ? () => _run(job) : null,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(icon, size: 20),
      label: Text(label),
    );
  }

  // ---- the receipt itself -------------------------------------------------

  Widget _paper(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sale = _data.sale;
    final merchant = _data.merchant;
    final paid = sale.paymentStatus == 'PAID';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.surface),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_loaded) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _data.businessName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final line in [
                    merchant?.address,
                    if ((merchant?.phone ?? '').trim().isNotEmpty)
                      'Tel: ${merchant!.phone.trim()}',
                    if ((merchant?.tpin ?? '').trim().isNotEmpty)
                      'TPIN: ${merchant!.tpin.trim()}',
                  ])
                    if ((line ?? '').trim().isNotEmpty)
                      Text(
                        line!.trim(),
                        textAlign: TextAlign.center,
                        style: _muted(theme),
                      ),
                  _rule(),
                  _kv(context, 'Receipt no.', _data.receiptNumber),
                  _kv(context, 'Sale no.', sale.saleNumber),
                  if (_data.soldAtLabel != null)
                    _kv(context, 'Date', _data.soldAtLabel!),
                  if ((sale.createdBy ?? '').isNotEmpty)
                    _kv(context, 'Served by', sale.createdBy!),
                  if ((sale.customerName ?? '').isNotEmpty)
                    _kv(context, 'Customer', sale.customerName!),
                  if ((sale.customerPhone ?? '').isNotEmpty)
                    _kv(context, 'Phone', sale.customerPhone!),
                  _rule(),
                  if (_data.items.isEmpty)
                    Text('No items on this sale.', style: _muted(theme))
                  else
                    for (final item in _data.items) _item(context, item),
                  _rule(),
                  _kv(context, 'Subtotal (ex VAT)', formatMoney(sale.subtotal)),
                  if (sale.discountAmount > 0)
                    _kv(
                      context,
                      'Discount',
                      '-${formatMoney(sale.discountAmount)}',
                    ),
                  _kv(context, 'VAT', formatMoney(sale.vatAmount)),
                  const SizedBox(height: Gap.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(Radii.control),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: Gap.md,
                        horizontal: Gap.lg,
                      ),
                      child: Text(
                        'Total ${formatMoney(sale.totalAmount)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  _rule(),
                  if (sale.payments.isEmpty)
                    _kv(context, 'Amount paid', formatMoney(sale.amountPaid))
                  else ...[
                    for (final p in sale.payments) _payment(context, p),
                    _kv(context, 'Amount paid', formatMoney(sale.amountPaid)),
                  ],
                  if (sale.changeGiven > 0) ...[
                    const SizedBox(height: Gap.sm),
                    Text(
                      'Change ${formatMoney(sale.changeGiven)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (!paid) ...[
                    const SizedBox(height: Gap.sm),
                    Text(
                      'Balance due ${formatMoney(sale.balanceDue)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_data.hasFiscalDetails) ...[
                    _rule(),
                    _fiscal(context, _data.fiscal!),
                  ],
                  _rule(),
                  Text(
                    _data.footer,
                    textAlign: TextAlign.center,
                    style: _muted(theme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _muted(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );

  Widget _rule() => const Padding(
    padding: EdgeInsets.symmetric(vertical: Gap.md),
    child: Divider(),
  );

  /// A label on the left and its value on the right. Both sides can wrap, so a
  /// long label or value never overflows at large text sizes.
  Widget _kv(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: Text(label, style: _muted(theme))),
          const SizedBox(width: Gap.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, SaleItem item) {
    final theme = Theme.of(context);
    final detail =
        '${item.quantity} × ${formatMoney(item.unitPrice)}'
        '${item.vatRate > 0 ? ' · VAT ${item.vatRate.toStringAsFixed(0)}%' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(detail, style: _muted(theme)),
                if (item.discountAmount > 0)
                  Text(
                    'Discount -${formatMoney(item.discountAmount)}',
                    style: _muted(theme),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          Text(
            formatMoney(item.lineTotal),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payment(BuildContext context, Payment p) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv(
          context,
          p.paymentMethodName.isEmpty ? 'Payment' : p.paymentMethodName,
          formatMoney(p.amount),
        ),
        if (p.amountTendered > p.amount)
          Padding(
            padding: const EdgeInsets.only(left: Gap.md),
            child: _kv(context, 'Tendered', formatMoney(p.amountTendered)),
          ),
        if ((p.transactionReference ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: Gap.md),
            child: _kv(context, 'Reference', p.transactionReference!),
          ),
        if (p.paymentStatus != 'SUCCESS')
          Text(
            'Payment ${p.paymentStatus.toLowerCase()}',
            style: _muted(theme),
          ),
      ],
    );
  }

  Widget _fiscal(BuildContext context, ReceiptInfo f) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verified = f.zraVerified && f.zraStatus == 'SUCCESS';
    final failed = f.zraStatus == 'FAILED';
    final status = verified
        ? 'Verified'
        : switch (f.zraStatus) {
            'FAILED' => 'Not accepted',
            'PENDING' || 'RETRYING' => 'Awaiting confirmation',
            final other => other ?? '',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              verified
                  ? Icons.verified_outlined
                  : failed
                  ? Icons.error_outline
                  : Icons.schedule,
              size: 18,
              color: verified
                  ? scheme.primary
                  : failed
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                'ZRA fiscal invoice',
                style: theme.textTheme.labelLarge,
              ),
            ),
            Flexible(
              child: Text(
                status,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        if (f.zraInvoiceNo != null)
          _kv(context, 'Invoice no.', '${f.zraInvoiceNo}'),
        if (f.zraReceiptNo != null)
          _kv(context, 'Fiscal receipt no.', '${f.zraReceiptNo}'),
        if ((f.zraReceiptSignature ?? '').isNotEmpty)
          _kv(context, 'Signature', f.zraReceiptSignature!),
        if ((f.zraSdcId ?? '').isNotEmpty) _kv(context, 'SDC ID', f.zraSdcId!),
        if ((f.zraMrcNo ?? '').isNotEmpty) _kv(context, 'MRC no.', f.zraMrcNo!),
        if ((f.zraReceiptDate ?? '').isNotEmpty)
          _kv(context, 'Fiscal date', f.zraReceiptDate!),
        if (!verified && !failed)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              'The tax authority has not confirmed this sale yet. Reopen the '
              'receipt from Sales history later to print the verified copy.',
              style: _muted(theme),
            ),
          ),
      ],
    );
  }
}
