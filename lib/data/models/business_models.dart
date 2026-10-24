import 'json_utils.dart';

/// `CustomerResponse`.
class Customer {
  const Customer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.tpin,
    required this.address,
    required this.isActive,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? email;
  final String? tpin;
  final String? address;
  final bool isActive;

  String get fullName => '$firstName $lastName'.trim();

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: toInt(json['id']),
    firstName: toStr(json['firstName']),
    lastName: toStr(json['lastName']),
    phone: toStrOrNull(json['phone']),
    email: toStrOrNull(json['email']),
    tpin: toStrOrNull(json['tpin']),
    address: toStrOrNull(json['address']),
    isActive: toBool(json['isActive'], true),
  );
}

/// `InventoryMovementResponse`.
class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productName,
    required this.movementType,
    required this.quantity,
    required this.notes,
    required this.performedBy,
    required this.createdAt,
  });

  final int id;
  final String productName;
  final String movementType;
  final int quantity;
  final String? notes;
  final String? performedBy;
  final DateTime? createdAt;

  factory InventoryMovement.fromJson(Map<String, dynamic> json) =>
      InventoryMovement(
        id: toInt(json['id']),
        productName: toStr(json['productName']),
        movementType: toStr(json['movementType']),
        quantity: toInt(json['quantity']),
        notes: toStrOrNull(json['notes']),
        performedBy: toStrOrNull(json['performedBy']),
        createdAt: toDateTime(json['createdAt']),
      );
}

/// `ReconciliationResponse` (end-of-day cash-up).
class Reconciliation {
  const Reconciliation({
    required this.id,
    required this.businessDate,
    required this.openingFloat,
    required this.expectedTotal,
    required this.declaredTotal,
    required this.varianceTotal,
    required this.status,
    required this.notes,
    required this.submittedBy,
    required this.lines,
  });

  final int id;
  final String businessDate;
  final double openingFloat;
  final double expectedTotal;
  final double declaredTotal;
  final double varianceTotal;
  final String status;
  final String? notes;
  final String? submittedBy;
  final List<ReconciliationLine> lines;

  factory Reconciliation.fromJson(Map<String, dynamic> json) => Reconciliation(
    id: toInt(json['id']),
    businessDate: toStr(json['businessDate']),
    openingFloat: toDouble(json['openingFloat']),
    expectedTotal: toDouble(json['expectedTotal']),
    declaredTotal: toDouble(json['declaredTotal']),
    varianceTotal: toDouble(json['varianceTotal']),
    status: toStr(json['status']),
    notes: toStrOrNull(json['notes']),
    submittedBy: toStrOrNull(json['submittedBy']),
    lines: toMapList(json['lines']).map(ReconciliationLine.fromJson).toList(),
  );
}

/// One tender line inside a [Reconciliation].
class ReconciliationLine {
  const ReconciliationLine({
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.expectedAmount,
    required this.declaredAmount,
    required this.variance,
    required this.flagged,
  });

  final int paymentMethodId;
  final String paymentMethodName;
  final double expectedAmount;
  final double declaredAmount;
  final double variance;
  final bool flagged;

  factory ReconciliationLine.fromJson(Map<String, dynamic> json) =>
      ReconciliationLine(
        paymentMethodId: toInt(json['paymentMethodId']),
        paymentMethodName: toStr(json['paymentMethodName']),
        expectedAmount: toDouble(json['expectedAmount']),
        declaredAmount: toDouble(json['declaredAmount']),
        variance: toDouble(json['variance']),
        flagged: toBool(json['flagged']),
      );
}
