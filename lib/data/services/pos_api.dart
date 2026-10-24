import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../models/auth_models.dart';
import '../models/business_models.dart';
import '../models/catalog_models.dart';
import '../models/merchant_models.dart';
import '../models/report_models.dart';
import '../models/json_utils.dart';

/// Auth, merchant, catalogue, customer and dashboard endpoints.
class PosApi {
  PosApi(this._client);

  final ApiClient _client;

  // ---- Auth (public) ----

  Future<AuthResponse> login({
    required String username,
    required String password,
  }) async {
    final json = await _client.post('/auth/login', body: {
      'username': username,
      'password': password,
    });
    return AuthResponse.fromJson(_map(json));
  }

  Future<AuthResponse> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String username,
    required String password,
  }) async {
    final json = await _client.post('/auth/register', body: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber,
      'username': username,
      'password': password,
    });
    return AuthResponse.fromJson(_map(json));
  }

  // ---- Merchant ----

  Future<MerchantProfile> getMerchant() async =>
      MerchantProfile.fromJson(_map(await _client.get('/merchant')));

  Future<MerchantProfile> updateMerchant(Map<String, dynamic> body) async =>
      MerchantProfile.fromJson(_map(await _client.put('/merchant', body: body)));

  // ---- Dashboard ----

  Future<Dashboard> getDashboard() async =>
      Dashboard.fromJson(_map(await _client.get('/dashboard')));

  // ---- Categories ----

  Future<List<Category>> listCategories() async =>
      _list(await _client.get('/categories')).map(Category.fromJson).toList();

  Future<Category> createCategory({
    required String name,
    String? description,
  }) async =>
      Category.fromJson(_map(await _client.post('/categories', body: {
        'name': name,
        'description': description,
      })));

  Future<Category> updateCategory(
    int id, {
    required String name,
    String? description,
  }) async =>
      Category.fromJson(_map(await _client.put('/categories/$id', body: {
        'name': name,
        'description': description,
      })));

  Future<void> deleteCategory(int id) => _client.delete('/categories/$id');

  // ---- Products ----

  Future<List<Product>> listProducts() async =>
      _list(await _client.get('/products')).map(Product.fromJson).toList();

  Future<List<Product>> lowStockProducts() async =>
      _list(await _client.get('/products/low-stock')).map(Product.fromJson).toList();

  Future<Product> getProduct(int id) async =>
      Product.fromJson(_map(await _client.get('/products/$id')));

  Future<Product> createProduct(Map<String, dynamic> body) async =>
      Product.fromJson(_map(await _client.post('/products', body: body)));

  Future<Product> updateProduct(int id, Map<String, dynamic> body) async =>
      Product.fromJson(_map(await _client.put('/products/$id', body: body)));

  Future<void> deleteProduct(int id) => _client.delete('/products/$id');

  // ---- Payment methods ----

  Future<List<PaymentMethod>> listPaymentMethods() async =>
      _list(await _client.get('/payment-methods'))
          .map(PaymentMethod.fromJson)
          .toList();

  // ---- Customers ----

  Future<List<Customer>> listCustomers() async =>
      _list(await _client.get('/customers')).map(Customer.fromJson).toList();

  /// Returns null when no customer has this phone number (the API answers 404).
  Future<Customer?> findCustomerByPhone(String phone) async {
    try {
      final json =
          await _client.get('/customers/search', query: {'phone': phone});
      if (json == null) return null;
      return Customer.fromJson(_map(json));
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<Customer> createCustomer(Map<String, dynamic> body) async =>
      Customer.fromJson(_map(await _client.post('/customers', body: body)));

  Future<Customer> updateCustomer(int id, Map<String, dynamic> body) async =>
      Customer.fromJson(_map(await _client.put('/customers/$id', body: body)));

  Future<void> deleteCustomer(int id) => _client.delete('/customers/$id');

  // ---- helpers ----

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map) return Map<String, dynamic>.from(json);
    throw const FormatException('Expected a JSON object from the server.');
  }

  static List<Map<String, dynamic>> _list(Object? json) => toMapList(json);
}
