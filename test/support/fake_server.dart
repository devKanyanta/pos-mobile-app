import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kantemba/core/api/token_store.dart';
import 'package:kantemba/core/session/session.dart';

/// Token store that never touches the platform keystore.
class MemoryTokenStore extends TokenStore {
  String? _token;
  String? _username;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<String?> readUsername() async => _username;

  @override
  Future<void> save({required String token, required String username}) async {
    _token = token;
    _username = username;
  }

  @override
  Future<void> clear() async {
    _token = null;
    _username = null;
  }
}

/// A tiny fake of the POS backend for widget tests.
class FakeServer {
  FakeServer({this.role = 'CASHIER'});

  final String role;

  /// Products the barcode endpoint knows, keyed by canonical barcode.
  final Map<String, Map<String, dynamic>> products = {};

  /// Every request received, in order.
  final List<http.Request> requests = [];

  /// When true, every call fails like an unreachable server.
  bool offline = false;

  /// When set, adjustment requests fail with this server message.
  String? adjustmentError;

  /// When set, device registration fails with this server message (503).
  String? deviceRegisterError;

  /// What `GET /sync/catalog` knows. A pull without `since` returns all of
  /// [catalogProducts]; a pull with it returns only those whose id is in
  /// [catalogChangedIds]. `productIds` is always every id.
  final Map<int, Map<String, dynamic>> catalogProducts = {};
  final Set<int> catalogChangedIds = {};
  String catalogServerTime = '2026-11-12T10:00:00.123456';

  /// When true, `GET /sync/catalog` fails with a 500.
  bool catalogFails = false;

  /// Client sale ids the fake server has recorded (from uploads).
  final Set<String> uploadedSaleIds = {};

  /// Uploaded sales the fake server rejects, with this error.
  final Map<String, String> rejectedSaleIds = {};

  /// When set, `POST /sync/sales` is refused whole with this status.
  int? uploadFailureStatus;

  /// When true, the upload answer carries no results at all.
  bool uploadAnswersNothing = false;

  /// When set, `POST /sync/sales` records the sales but then drops the
  /// connection, like a reply lost on the way back.
  bool uploadLosesReply = false;

  /// Conflict codes the fake attaches to every sale it creates.
  List<String> uploadConflicts = [];

  /// The largest batch the fake accepts, like `SYNC_MAX_BATCH_SIZE`.
  int maxBatchSize = 100;

  /// When true, `GET /products/by-barcode` fails with a 500.
  bool barcodeFails = false;

  /// When set, `POST /sales` is refused with this status and a stock message.
  int? saleFailureStatus;

  /// `GET /merchant` answer; null makes the endpoint fail with 404.
  Map<String, dynamic>? merchant;

  /// `GET /receipts/sale/{id}` answer; null makes the endpoint fail with 404.
  Map<String, dynamic>? receipt;

  /// Customers returned by `GET /customers`.
  List<Map<String, dynamic>> customers = [];

  /// Movement rows returned by the history endpoints.
  List<Map<String, dynamic>> movements = [];

  Map<String, dynamic> saleResponse = {
    'id': 7,
    'saleNumber': 'S-0007',
    'subtotal': 10.0,
    'vatAmount': 1.6,
    'totalAmount': 11.6,
    'amountPaid': 11.6,
    'balanceDue': 0.0,
    'changeGiven': 0.0,
    'paymentStatus': 'PAID',
    'saleStatus': 'ACTIVE',
    'items': <Object>[],
    'payments': <Object>[],
  };

  Iterable<http.Request> posts(String path) =>
      requests.where((r) => r.method == 'POST' && r.url.path == '/api/v1$path');

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    requests.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');

    if (path == '/sync/devices/register' && request.method == 'POST') {
      if (deviceRegisterError != null) {
        return _json({'message': deviceRegisterError}, 503);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'id': 1,
        'deviceId': body['deviceId'],
        'name': body['name'],
        'model': body['model'],
        'appVersion': body['appVersion'],
        'active': true,
        'pendingQueueSize': 0,
      });
    }
    if (path == '/sync/catalog' && request.method == 'GET') {
      if (catalogFails) return _json({'message': 'boom'}, 500);
      final since = request.url.queryParameters['since'];
      final sent = since == null
          ? catalogProducts.values.toList()
          : [
              for (final id in catalogChangedIds)
                if (catalogProducts[id] != null) catalogProducts[id]!,
            ];
      return _json({
        'serverTime': catalogServerTime,
        'full': since == null,
        'products': sent,
        'categories': [
          {'id': 1, 'name': 'Groceries'},
        ],
        'paymentMethods': [
          {
            'id': 1,
            'name': 'Cash',
            'code': 'CASH',
            'isActive': true,
            'type': 'CASH',
            'requiresReference': false,
          },
        ],
        'productIds': catalogProducts.keys.toList(),
      });
    }
    if (path == '/sync/heartbeat' && request.method == 'POST') {
      return _json({'id': 1, 'deviceId': bodyOf(request)['deviceId']});
    }
    if (path == '/sync/sales' && request.method == 'POST') {
      if (uploadFailureStatus != null) {
        return _json({
          'message': 'Device has been deactivated by a manager',
        }, uploadFailureStatus!);
      }
      final body = bodyOf(request);
      final sales = (body['sales'] as List).cast<Map<String, dynamic>>();
      if (sales.length > maxBatchSize) {
        return _json({'message': 'A sync batch may contain at most $maxBatchSize sales'}, 400);
      }
      final results = <Map<String, dynamic>>[];
      for (final sale in sales) {
        final id = sale['clientSaleId'] as String;
        if (rejectedSaleIds.containsKey(id)) {
          results.add({
            'clientSaleId': id,
            'status': 'REJECTED',
            'conflicts': <String>[],
            'error': rejectedSaleIds[id],
          });
        } else if (!uploadedSaleIds.add(id)) {
          results.add({
            'clientSaleId': id,
            'status': 'DUPLICATE',
            'saleNumber': 'S-$id',
            'conflicts': <String>[],
          });
        } else {
          results.add({
            'clientSaleId': id,
            'status': 'CREATED',
            'saleNumber': 'S-$id',
            'conflicts': uploadConflicts,
          });
        }
      }
      if (uploadLosesReply) throw http.ClientException('reply lost');
      return _json({'results': uploadAnswersNothing ? <Object>[] : results});
    }
    if (path == '/auth/login') {
      return _json({
        'token': 't',
        'username': 'tester',
        'roles': [role],
      });
    }
    if (path == '/merchant' && request.method == 'GET') {
      return merchant == null
          ? _json({'message': 'No merchant profile'}, 404)
          : _json(merchant!);
    }
    if (path.startsWith('/receipts/sale/')) {
      return receipt == null
          ? _json({'message': 'No receipt'}, 404)
          : _json(receipt!);
    }
    if (path == '/customers' && request.method == 'GET') {
      return _json(customers);
    }
    if (path == '/payment-methods') {
      return _json([
        {
          'id': 1,
          'name': 'Cash',
          'code': 'CASH',
          'isActive': true,
          'type': 'CASH',
          'requiresReference': false,
        },
        {
          'id': 2,
          'name': 'MTN Mobile Money',
          'code': 'MTN',
          'isActive': true,
          'type': 'MOBILE_MONEY',
          'requiresReference': true,
        },
      ]);
    }
    if (path == '/products/by-barcode') {
      if (barcodeFails) return _json({'message': 'boom'}, 500);
      final product = products[request.url.queryParameters['barcode']];
      return product != null
          ? _json(product)
          : _json({
              'status': 404,
              'message':
                  'No product found for barcode ${request.url.queryParameters['barcode']}',
            }, 404);
    }
    if (path == '/products' && request.method == 'GET') {
      return _json(products.values.toList());
    }
    if (path == '/products' && request.method == 'POST') {
      return _json({
        ...jsonDecode(request.body) as Map<String, dynamic>,
        'id': 99,
      }, 201);
    }
    if (path == '/inventory-movements/restock' && request.method == 'POST') {
      return _json({'id': 1, 'movementType': 'RESTOCK'}, 201);
    }
    if (path == '/inventory-movements/adjustment' && request.method == 'POST') {
      if (adjustmentError != null) {
        return _json({'message': adjustmentError}, 400);
      }
      return _json({'id': 2, 'movementType': 'ADJUSTMENT'}, 201);
    }
    if (path == '/inventory-movements' ||
        path.startsWith('/inventory-movements/product/')) {
      return _json(movements);
    }
    if (path == '/sales' && request.method == 'POST') {
      if (saleFailureStatus != null) {
        return _json({'message': 'Not enough stock'}, saleFailureStatus!);
      }
      return _json(saleResponse, 201);
    }
    return _json({'message': 'No endpoint matches this path'}, 404);
  }

  MockClient get client => MockClient(_handle);

  /// A session signed in as [role] that talks to this fake.
  Future<Session> signedInSession() async {
    final session = Session(tokenStore: MemoryTokenStore(), httpClient: client);
    await session.signIn(username: 'tester', password: 'secret');
    requests.clear();
    return session;
  }
}

Map<String, dynamic> productJson(
  int id,
  String barcode, {
  String name = 'Milk',
  double price = 10,
  int stock = 5,
  bool active = true,
}) => {
  'id': id,
  'name': name,
  'barcode': barcode,
  'price': price,
  'stockQuantity': stock,
  'active': active,
  'vatRate': 16.0,
  'trackInventory': true,
};

/// A product as `GET /sync/catalog` sends it.
Map<String, dynamic> catalogItemJson(
  int id,
  String name, {
  String? barcode,
  double price = 10,
  int stock = 5,
  bool active = true,
  int? categoryId,
}) => {
  'id': id,
  'name': name,
  'barcode': barcode,
  'price': price,
  'vatRate': 16.0,
  'zraTaxType': 'A',
  'trackInventory': true,
  'stockQuantity': stock,
  'active': active,
  'categoryId': categoryId,
};
