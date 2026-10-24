import 'json_utils.dart';

/// `ReceiptResponse`: the receipt number and the fiscal (ZRA) details the
/// server records for a sale. The fiscal fields stay empty until the tax
/// authority's device has signed the invoice, which can happen after the sale.
class ReceiptInfo {
  const ReceiptInfo({
    required this.receiptNumber,
    required this.zraStatus,
    required this.zraVerified,
    required this.zraInvoiceNo,
    required this.zraReceiptNo,
    required this.zraReceiptSignature,
    required this.zraSdcId,
    required this.zraMrcNo,
    required this.zraQrCodeUrl,
    required this.zraReceiptDate,
  });

  final String receiptNumber;

  /// PENDING, RETRYING, SUCCESS, FAILED, or null when the sale is not reported.
  final String? zraStatus;
  final bool zraVerified;
  final int? zraInvoiceNo;
  final int? zraReceiptNo;
  final String? zraReceiptSignature;
  final String? zraSdcId;
  final String? zraMrcNo;
  final String? zraQrCodeUrl;
  final String? zraReceiptDate;

  factory ReceiptInfo.fromJson(Map<String, dynamic> json) => ReceiptInfo(
    receiptNumber: toStr(json['receiptNumber']),
    zraStatus: toStrOrNull(json['zraStatus']),
    zraVerified: toBool(json['zraVerified']),
    zraInvoiceNo: toIntOrNull(json['zraInvoiceNo']),
    zraReceiptNo: toIntOrNull(json['zraReceiptNo']),
    zraReceiptSignature: toStrOrNull(json['zraReceiptSignature']),
    zraSdcId: toStrOrNull(json['zraSdcId']),
    zraMrcNo: toStrOrNull(json['zraMrcNo']),
    zraQrCodeUrl: toStrOrNull(json['zraQrCodeUrl']),
    zraReceiptDate: toStrOrNull(json['zraReceiptDate']),
  );
}
