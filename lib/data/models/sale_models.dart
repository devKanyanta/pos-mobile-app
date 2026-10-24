import 'json_utils.dart';

/// One line in a sale to send to `POST /sales`.
class SaleItemInput {
  const SaleItemInput({
    required this.productId,
    required this.quantity,
    this.discountAmount = 0,
  });

  final int productId;
  final int quantity;
  final double discountAmount;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity': quantity,
        'discountAmount': discountAmount,
      };
}

/// A tender to send with `POST /sales` or `POST /sales/{id}/payments`.
class PaymentInput {
  const PaymentInput({
    required this.paymentMethodId,
    required this.amount,
    this.transactionReference,
    this.payerPhone,
  });

  final int paymentMethodId;
  final double amount;
  final String? transactionReference;
  final String? payerPhone;

  Map<String, dynamic> toJson() => {
        'paymentMethodId': paymentMethodId,
        'amount': amount,
        if (transactionReference != null)
          'transactionReference': transactionReference,
        if (payerPhone != null) 'payerPhone': payerPhone,
      };
}

/// `SaleItemResponse`.
class SaleItem {
  const SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.totalAmount,
    required this.refundedQuantity,
    required this.itemStatus,
  });

  final int id;
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final double totalAmount;
  final int refundedQuantity;
  final String itemStatus;

  int get remainingQuantity => quantity - refundedQuantity;

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: toInt(json['id']),
        productId: toInt(json['productId']),
        productName: toStr(json['productName']),
        quantity: toInt(json['quantity']),
        unitPrice: toDouble(json['unitPrice']),
        lineTotal: toDouble(json['lineTotal']),
        totalAmount: toDouble(json['totalAmount']),
        refundedQuantity: toInt(json['refundedQuantity']),
        itemStatus: toStr(json['itemStatus'], 'ACTIVE'),
      );
}

/// `PaymentResponse`.
class Payment {
  const Payment({
    required this.id,
    required this.paymentMethodName,
    required this.paymentMethodType,
    required this.amount,
    required this.amountTendered,
    required this.changeAmount,
    required this.transactionReference,
    required this.paymentStatus,
    required this.paidAt,
    required this.receiptNumber,
  });

  final int id;
  final String paymentMethodName;
  final String paymentMethodType;
  final double amount;
  final double amountTendered;
  final double changeAmount;
  final String? transactionReference;
  final String paymentStatus;
  final DateTime? paidAt;
  final String? receiptNumber;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: toInt(json['id']),
        paymentMethodName: toStr(json['paymentMethodName']),
        paymentMethodType: toStr(json['paymentMethodType']),
        amount: toDouble(json['amount']),
        amountTendered: toDouble(json['amountTendered']),
        changeAmount: toDouble(json['changeAmount']),
        transactionReference: toStrOrNull(json['transactionReference']),
        paymentStatus: toStr(json['paymentStatus'], 'SUCCESS'),
        paidAt: toDateTime(json['paidAt']),
        receiptNumber: toStrOrNull(json['receiptNumber']),
      );
}

/// `SaleResponse`, trimmed to the fields the app displays.
class Sale {
  const Sale({
    required this.id,
    required this.saleNumber,
    required this.customerId,
    required this.customerName,
    required this.subtotal,
    required this.discountAmount,
    required this.vatAmount,
    required this.totalAmount,
    required this.amountPaid,
    required this.balanceDue,
    required this.changeGiven,
    required this.refundedAmount,
    required this.paymentStatus,
    required this.saleStatus,
    required this.notes,
    required this.createdBy,
    required this.soldAt,
    required this.receiptId,
    required this.receiptNumber,
    required this.zraStatus,
    required this.needsReview,
    required this.items,
    required this.payments,
  });

  final int id;
  final String saleNumber;
  final int? customerId;
  final String? customerName;
  final double subtotal;
  final double discountAmount;
  final double vatAmount;
  final double totalAmount;
  final double amountPaid;
  final double balanceDue;
  final double changeGiven;
  final double refundedAmount;
  final String paymentStatus;
  final String saleStatus;
  final String? notes;
  final String? createdBy;
  final DateTime? soldAt;
  final int? receiptId;
  final String? receiptNumber;
  final String? zraStatus;
  final bool needsReview;
  final List<SaleItem> items;
  final List<Payment> payments;

  bool get isVoided => saleStatus == 'VOIDED';
  bool get isFullyPaid => paymentStatus == 'PAID';
  bool get hasPayments => payments.isNotEmpty;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: toInt(json['id']),
        saleNumber: toStr(json['saleNumber']),
        customerId: toIntOrNull(json['customerId']),
        customerName: toStrOrNull(json['customerName']),
        subtotal: toDouble(json['subtotal']),
        discountAmount: toDouble(json['discountAmount']),
        vatAmount: toDouble(json['vatAmount']),
        totalAmount: toDouble(json['totalAmount']),
        amountPaid: toDouble(json['amountPaid']),
        balanceDue: toDouble(json['balanceDue']),
        changeGiven: toDouble(json['changeGiven']),
        refundedAmount: toDouble(json['refundedAmount']),
        paymentStatus: toStr(json['paymentStatus'], 'PENDING'),
        saleStatus: toStr(json['saleStatus'], 'ACTIVE'),
        notes: toStrOrNull(json['notes']),
        createdBy: toStrOrNull(json['createdBy']),
        soldAt: toDateTime(json['soldAt'] ?? json['createdAt']),
        receiptId: toIntOrNull(json['receiptId']),
        receiptNumber: toStrOrNull(json['receiptNumber']),
        zraStatus: toStrOrNull(json['zraStatus']),
        needsReview: toBool(json['needsReview']),
        items: toMapList(json['items']).map(SaleItem.fromJson).toList(),
        payments: toMapList(json['payments']).map(Payment.fromJson).toList(),
      );
}
