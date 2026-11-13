import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/receipt_models.dart';
import 'receipt_data.dart';

/// Width of the receipt itself, matching an 80 mm thermal roll.
const double _receiptWidth = 80 * PdfPageFormat.mm;

/// Renders [data] as a PDF.
///
/// With no [format] the page is an 80 mm roll as tall as the receipt, which is
/// what is saved or shared. For a sheet [format] (A4, Letter) the receipt is
/// laid out as an 80 mm column centred on the page, flowing onto more pages if
/// it is long. Text is kept to characters the built-in PDF font can draw.
Future<Uint8List> buildReceiptPdf(
  ReceiptData data, {
  PdfPageFormat? format,
}) async {
  final doc = pw.Document(
    title: 'Receipt ${data.receiptNumber}',
    author: data.businessName,
  );
  final content = _content(data);

  if (format == null) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 5 * PdfPageFormat.mm,
          marginRight: 5 * PdfPageFormat.mm,
          marginTop: 6 * PdfPageFormat.mm,
          marginBottom: 6 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
    );
  } else {
    final side = ((format.width - _receiptWidth) / 2).clamp(
      PdfPageFormat.cm,
      format.width,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: format.copyWith(
          marginLeft: side,
          marginRight: side,
          marginTop: 1.5 * PdfPageFormat.cm,
          marginBottom: 1.5 * PdfPageFormat.cm,
        ),
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        build: (_) => content,
      ),
    );
  }
  return doc.save();
}

List<pw.Widget> _content(ReceiptData data) {
  final sale = data.sale;
  final merchant = data.merchant;
  final fiscal = data.fiscal;

  const small = pw.TextStyle(fontSize: 8);
  final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  const normal = pw.TextStyle(fontSize: 9);

  pw.Widget rule() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Divider(thickness: 0.5, height: 0.5),
  );

  pw.Widget row(String label, String value, {pw.TextStyle? style}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(label, style: style ?? normal)),
            pw.SizedBox(width: 6),
            pw.Text(value, style: style ?? normal),
          ],
        ),
      );

  pw.Widget centered(String text, {pw.TextStyle? style}) =>
      pw.Text(text, style: style ?? normal, textAlign: pw.TextAlign.center);

  final paid = sale.paymentStatus == 'PAID';

  return [
    centered(
      data.businessName,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    if (merchant != null && merchant.address.trim().isNotEmpty)
      centered(merchant.address.trim(), style: small),
    if (merchant != null && merchant.phone.trim().isNotEmpty)
      centered('Tel: ${merchant.phone.trim()}', style: small),
    if (merchant != null && merchant.tpin.trim().isNotEmpty)
      centered('TPIN: ${merchant.tpin.trim()}', style: small),
    rule(),
    centered(
      paid ? 'SALES RECEIPT' : 'SALES RECEIPT - BALANCE DUE',
      style: bold,
    ),
    pw.SizedBox(height: 4),
    row('Receipt no.', data.receiptNumber),
    row('Sale no.', sale.saleNumber),
    if (data.soldAtLabel != null) row('Date', data.soldAtLabel!),
    if ((sale.createdBy ?? '').isNotEmpty) row('Served by', sale.createdBy!),
    if ((sale.customerName ?? '').isNotEmpty)
      row('Customer', sale.customerName!),
    if ((sale.customerPhone ?? '').isNotEmpty)
      row('Phone', sale.customerPhone!),
    rule(),
    pw.Row(
      children: [
        pw.Expanded(child: pw.Text('Item', style: bold)),
        pw.Text('Amount', style: bold),
      ],
    ),
    pw.SizedBox(height: 3),
    for (final item in data.items)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(item.productName, style: normal),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${item.quantity} x ${formatMoney(item.unitPrice)}'
                  '${item.vatRate > 0 ? '  (VAT ${item.vatRate.toStringAsFixed(0)}%)' : ''}',
                  style: small,
                ),
                pw.Text(formatMoney(item.lineTotal), style: normal),
              ],
            ),
            if (item.discountAmount > 0)
              row(
                '  Discount',
                '-${formatMoney(item.discountAmount)}',
                style: small,
              ),
          ],
        ),
      ),
    rule(),
    row('Subtotal (ex VAT)', formatMoney(sale.subtotal)),
    if (sale.discountAmount > 0)
      row('Discount', '-${formatMoney(sale.discountAmount)}'),
    row('VAT', formatMoney(sale.vatAmount)),
    pw.SizedBox(height: 3),
    row(
      'TOTAL',
      formatMoney(sale.totalAmount),
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
    rule(),
    for (final p in sale.payments)
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          row(
            p.paymentMethodName.isEmpty ? 'Payment' : p.paymentMethodName,
            formatMoney(p.amount),
          ),
          if (p.amountTendered > p.amount)
            row('  Tendered', formatMoney(p.amountTendered), style: small),
          if ((p.transactionReference ?? '').isNotEmpty)
            row('  Ref', p.transactionReference!, style: small),
        ],
      ),
    row('Amount paid', formatMoney(sale.amountPaid)),
    if (sale.changeGiven > 0)
      row('Change', formatMoney(sale.changeGiven), style: bold),
    if (!paid) row('Balance due', formatMoney(sale.balanceDue), style: bold),
    if (sale.offline) ...[
      rule(),
      centered('OFFLINE RECEIPT', style: bold),
      centered(
        'Saved on the till. The ZRA fiscal invoice follows once the till '
        'is back online.',
        style: small,
      ),
    ],
    if (fiscal != null && fiscal.zraStatus != null)
      ..._fiscal(fiscal, small, bold, row, rule),
    rule(),
    centered(data.footer, style: small),
  ];
}

List<pw.Widget> _fiscal(
  ReceiptInfo fiscal,
  pw.TextStyle small,
  pw.TextStyle bold,
  pw.Widget Function(String, String, {pw.TextStyle? style}) row,
  pw.Widget Function() rule,
) {
  final verified = fiscal.zraVerified && fiscal.zraStatus == 'SUCCESS';
  return [
    rule(),
    pw.Text('ZRA FISCAL INVOICE', style: bold, textAlign: pw.TextAlign.center),
    pw.SizedBox(height: 3),
    row('Status', verified ? 'Verified' : fiscal.zraStatus ?? ''),
    if (fiscal.zraInvoiceNo != null)
      row('Invoice no.', '${fiscal.zraInvoiceNo}', style: small),
    if (fiscal.zraReceiptNo != null)
      row('Receipt no.', '${fiscal.zraReceiptNo}', style: small),
    if ((fiscal.zraReceiptSignature ?? '').isNotEmpty)
      row('Signature', fiscal.zraReceiptSignature!, style: small),
    if ((fiscal.zraSdcId ?? '').isNotEmpty)
      row('SDC ID', fiscal.zraSdcId!, style: small),
    if ((fiscal.zraMrcNo ?? '').isNotEmpty)
      row('MRC no.', fiscal.zraMrcNo!, style: small),
    if ((fiscal.zraReceiptDate ?? '').isNotEmpty)
      row('Fiscal date', fiscal.zraReceiptDate!, style: small),
    if (verified && (fiscal.zraQrCodeUrl ?? '').isNotEmpty) ...[
      pw.SizedBox(height: 6),
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: fiscal.zraQrCodeUrl!,
          width: 80,
          height: 80,
        ),
      ),
    ],
  ];
}
