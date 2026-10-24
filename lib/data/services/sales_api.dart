import 'dart:convert';

import '../../core/api/api_client.dart';
import '../models/json_utils.dart';
import '../models/sale_models.dart';

/// Sales, payments, refunds, voids and receipts endpoints.
class SalesApi {
  SalesApi(this._client);

  final ApiClient _client;

  /// `POST /sales`. [clientSaleId] makes retries idempotent.
  Future<Sale> createSale({
    required List<SaleItemInput> items,
    List<PaymentInput> payments = const [],
    int? customerId,
    double discountAmount = 0,
    String? notes,
    String? clientSaleId,
  }) async {
    final json = await _client.post(
      '/sales',
      body: {
        'items': items.map((e) => e.toJson()).toList(),
        if (payments.isNotEmpty)
          'payments': payments.map((e) => e.toJson()).toList(),
        'customerId': ?customerId,
        if (discountAmount > 0) 'discountAmount': discountAmount,
        'notes': ?(notes == null || notes.isEmpty ? null : notes),
        'clientSaleId': ?clientSaleId,
      },
    );
    return Sale.fromJson(_map(json));
  }

  Future<List<Sale>> listSales() async =>
      toMapList(await _client.get('/sales')).map(Sale.fromJson).toList();

  Future<List<Sale>> salesBetween(String from, String to) async => toMapList(
    await _client.get('/sales/date-range', query: {'from': from, 'to': to}),
  ).map(Sale.fromJson).toList();

  Future<Sale> getSale(int id) async =>
      Sale.fromJson(_map(await _client.get('/sales/$id')));

  Future<Sale> voidSale(int id) async =>
      Sale.fromJson(_map(await _client.post('/sales/$id/void')));

  /// `POST /sales/{id}/refund`. Omit [items] for a full refund of [saleItemIds].
  Future<Map<String, dynamic>> refund(
    int saleId, {
    List<int> saleItemIds = const [],
    List<Map<String, dynamic>> items = const [],
    String? reason,
    String? zraReasonCode,
    int? refundPaymentMethodId,
  }) async {
    final json = await _client.post(
      '/sales/$saleId/refund',
      body: {
        if (saleItemIds.isNotEmpty) 'saleItemIds': saleItemIds,
        if (items.isNotEmpty) 'items': items,
        'reason': ?(reason == null || reason.isEmpty ? null : reason),
        'zraReasonCode': ?zraReasonCode,
        'refundPaymentMethodId': ?refundPaymentMethodId,
      },
    );
    return _map(json);
  }

  /// `POST /sales/{saleId}/payments`.
  Future<Payment> addPayment(int saleId, PaymentInput input) async =>
      Payment.fromJson(
        _map(
          await _client.post('/sales/$saleId/payments', body: input.toJson()),
        ),
      );

  Future<List<Payment>> listPayments(int saleId) async =>
      toMapList(await _client.get('/sales/$saleId/payments'))
          .map(Payment.fromJson)
          .toList();

  /// `GET /receipts/sale/{saleId}`.
  Future<Map<String, dynamic>> receiptForSale(int saleId) async =>
      _map(await _client.get('/receipts/sale/$saleId'));

  /// `GET /receipts/{id}/print` as plain text for the receipt view.
  Future<String> receiptText(int receiptId, {int width = 42}) async {
    final bytes = await _client.getBytes(
      '/receipts/$receiptId/print',
      query: {'width': '$width'},
    );
    return utf8.decode(bytes);
  }

  /// `POST /receipts/{id}/reprint`.
  Future<void> reprintReceipt(int receiptId) =>
      _client.post('/receipts/$receiptId/reprint').then((_) {});

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map) return Map<String, dynamic>.from(json);
    throw const FormatException('Expected a JSON object from the server.');
  }
}
