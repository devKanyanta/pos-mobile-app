import 'package:printing/printing.dart';

import 'receipt_data.dart';
import 'receipt_pdf.dart';

/// Sends a receipt to a printer or saves it as a PDF.
///
/// This is the only code that talks to the platform's print and share
/// services, so tests can replace it with a fake.
class ReceiptOutput {
  const ReceiptOutput();

  /// Opens the system print dialog (any installed printer, or "Save as PDF").
  Future<void> print(ReceiptData data) async {
    await Printing.layoutPdf(
      name: data.fileName,
      onLayout: (format) => buildReceiptPdf(data, format: format),
    );
  }

  /// Hands the PDF to the system share sheet, where it can be saved to the
  /// device's files, sent by email or messaging, and so on.
  Future<void> savePdf(ReceiptData data) async {
    await Printing.sharePdf(
      bytes: await buildReceiptPdf(data),
      filename: data.fileName,
    );
  }
}
