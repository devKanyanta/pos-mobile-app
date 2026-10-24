import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/auth_models.dart';
import '../../data/services/pos_api.dart';
import '../../data/services/reports_api.dart';
import '../../data/services/sales_api.dart';
import '../api/api_client.dart';
import '../api/token_store.dart';

/// Default API root. Override at build time with
/// `--dart-define=KANTEMBA_API_URL=http://host:8081/api/v1`.
/// 10.0.2.2 reaches the host machine from the Android emulator.
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'KANTEMBA_API_URL',
  defaultValue: 'http://192.168.1.189:8081/api/v1',
);

/// Holds the signed-in user, the API base URL and the typed API services.
class Session extends ChangeNotifier {
  Session({TokenStore? tokenStore, FlutterSecureStorage? settingsStorage})
      : _tokenStore = tokenStore ?? TokenStore(),
        _settings = settingsStorage ?? const FlutterSecureStorage() {
    _rebuildServices();
  }

  static const _baseUrlKey = 'kantemba.baseUrl';

  final TokenStore _tokenStore;
  final FlutterSecureStorage _settings;
  ApiClient? _client;
  late PosApi pos;
  late SalesApi sales;
  late ReportsApi reports;

  String? _username;
  List<String> _roles = const [];
  String _baseUrl = kDefaultApiBaseUrl;
  bool _restored = false;

  bool get isRestored => _restored;
  bool get isSignedIn => _username != null;
  String? get username => _username;
  List<String> get roles => _roles;
  bool get isAdmin => _roles.contains('ADMIN');
  String get baseUrl => _baseUrl;

  /// Loads a saved token and API base URL at startup.
  Future<void> restore() async {
    final savedUrl = await _settings.read(key: _baseUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _baseUrl = savedUrl;
      _rebuildServices();
    }
    _username = await _tokenStore.readUsername();
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) _username = null;
    _restored = true;
    notifyListeners();
  }

  Future<void> signIn({required String username, required String password}) async {
    final AuthResponse auth = await pos.login(username: username, password: password);
    await _store(auth);
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String username,
    required String password,
  }) async {
    final AuthResponse auth = await pos.register(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phoneNumber: phoneNumber,
      username: username,
      password: password,
    );
    await _store(auth);
  }

  Future<void> _store(AuthResponse auth) async {
    await _tokenStore.save(token: auth.token, username: auth.username);
    _username = auth.username;
    _roles = auth.roles;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _tokenStore.clear();
    _username = null;
    _roles = const [];
    notifyListeners();
  }

  /// Saves a new API base URL and reconnects the services.
  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _settings.write(key: _baseUrlKey, value: trimmed);
    _baseUrl = trimmed;
    _rebuildServices();
    notifyListeners();
  }

  void _handleUnauthorized() {
    if (_username == null) return;
    _tokenStore.clear();
    _username = null;
    _roles = const [];
    notifyListeners();
  }

  void _rebuildServices() {
    _client?.close();
    final client = ApiClient(
      baseUrl: _baseUrl,
      tokenProvider: _tokenStore.readToken,
      onUnauthorized: _handleUnauthorized,
    );
    _client = client;
    pos = PosApi(client);
    sales = SalesApi(client);
    reports = ReportsApi(client);
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
