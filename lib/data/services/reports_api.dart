import '../../core/api/api_client.dart';
import '../models/business_models.dart';
import '../models/json_utils.dart';
import '../models/report_models.dart';

/// Reports, Z-report and end-of-day reconciliation endpoints.
class ReportsApi {
  ReportsApi(this._client);

  final ApiClient _client;

  /// `GET /reports/today` (all plans).
  Future<TodaySummary> today() async =>
      TodaySummary.fromJson(_map(await _client.get('/reports/today')));

  /// `GET /reports/sales/daily?date=yyyy-MM-dd` (SME plan).
  Future<DailySalesReport> dailySales(String date) async =>
      DailySalesReport.fromJson(
        _map(await _client.get('/reports/sales/daily', query: {'date': date})),
      );

  /// `GET /reports/sales/summary?from=&to=` (SME plan).
  Future<SalesSummaryReport> salesSummary(String from, String to) async =>
      SalesSummaryReport.fromJson(
        _map(
          await _client.get(
            '/reports/sales/summary',
            query: {'from': from, 'to': to},
          ),
        ),
      );

  /// `GET /reports/products/top?from=&to=&limit=` (SME plan).
  Future<List<ProductSummary>> topProducts(
    String from,
    String to, {
    int limit = 10,
  }) async => toMapList(
    await _client.get(
      '/reports/products/top',
      query: {'from': from, 'to': to, 'limit': '$limit'},
    ),
  ).map(ProductSummary.fromJson).toList();

  /// `GET /reports/inventory/value` (SME plan). Returned as a map because the
  /// screen only displays the totals and the low-stock list.
  Future<Map<String, dynamic>> inventoryValue() async =>
      _map(await _client.get('/reports/inventory/value'));

  /// `GET /reports/z-report?date=` (reconciliation feature). Returned as a map;
  /// the Z-report screen reads its sections directly.
  Future<Map<String, dynamic>> zReport({String? date}) async => _map(
    await _client.get(
      '/reports/z-report',
      query: date == null ? null : {'date': date},
    ),
  );

  /// `GET /reports/z-report/whatsapp?date=&phone=`.
  Future<Map<String, dynamic>> zReportWhatsAppText({
    required String phone,
    String? date,
  }) async {
    final query = {'phone': phone, 'date': ?date};
    return _map(await _client.get('/reports/z-report/whatsapp', query: query));
  }

  /// `POST /reports/z-report/whatsapp/send?date=` (WHATSAPP_SEND).
  Future<void> sendZReportWhatsApp({
    required String phone,
    String? date,
  }) async {
    await _client.post(
      '/reports/z-report/whatsapp/send',
      body: {'phone': phone},
      query: date == null ? null : {'date': date},
    );
  }

  /// `GET /reports/z-report/csv?date=` as raw bytes.
  Future<List<int>> zReportCsv({String? date}) => _client.getBytes(
    '/reports/z-report/csv',
    query: date == null ? null : {'date': date},
  );

  /// `GET /reports/z-report/pdf?date=` as raw bytes.
  Future<List<int>> zReportPdf({String? date}) => _client.getBytes(
    '/reports/z-report/pdf',
    query: date == null ? null : {'date': date},
  );

  /// `POST /reconciliations`. Resubmitting the same date replaces the cash-up.
  Future<Reconciliation> submitReconciliation({
    String? businessDate,
    required double openingFloat,
    required List<Map<String, dynamic>> declared,
    String? notes,
  }) async => Reconciliation.fromJson(
    _map(
      await _client.post(
        '/reconciliations',
        body: {
          'businessDate': ?businessDate,
          'openingFloat': openingFloat,
          'declared': declared,
          'notes': ?(notes == null || notes.isEmpty ? null : notes),
        },
      ),
    ),
  );

  Future<List<Reconciliation>> listReconciliations({
    String? from,
    String? to,
  }) async {
    final query = {'from': ?from, 'to': ?to};
    return toMapList(
      await _client.get(
        '/reconciliations',
        query: query.isEmpty ? null : query,
      ),
    ).map(Reconciliation.fromJson).toList();
  }

  Future<Reconciliation> getReconciliation(String date) async =>
      Reconciliation.fromJson(
        _map(await _client.get('/reconciliations/$date')),
      );

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map) return Map<String, dynamic>.from(json);
    throw const FormatException('Expected a JSON object from the server.');
  }
}
