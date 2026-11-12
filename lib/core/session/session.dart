import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../data/local/local_store.dart';
import '../../data/models/auth_models.dart';
import '../../data/services/pos_api.dart';
import '../../data/services/reports_api.dart';
import '../../data/services/sales_api.dart';
import '../../data/services/sync_api.dart';
import '../api/api_client.dart';
import '../api/token_store.dart';
import '../sync/device_identity.dart';

/// Default API root. Override at build time with
/// `--dart-define=KANTEMBA_API_URL=http://host:8081/api/v1`.
/// 10.0.2.2 reaches the host machine from the Android emulator.
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'KANTEMBA_API_URL',
  defaultValue: 'http://192.168.0.197:8081/api/v1',
);

/// Reported to the server when the till registers. Keep in step with the
/// `version:` in pubspec.yaml.
const String kAppVersion = '1.0.0+1';

/// Holds the signed-in user, the API base URL and the typed API services.
class Session extends ChangeNotifier {
  /// [httpClient] lets tests run the whole app against a fake server.
  /// Without a [localStore] the app runs online-only: no cached catalogue,
  /// no offline queue and no device registration.
  Session({
    TokenStore? tokenStore,
    FlutterSecureStorage? settingsStorage,
    this._localStore,
    this._httpClient,
  }) : _tokenStore = tokenStore ?? TokenStore(),
       _settings = settingsStorage ?? const FlutterSecureStorage() {
    _rebuildServices();
  }

  static const _baseUrlKey = 'kantemba.baseUrl';
  static const _themeModeKey = 'kantemba.themeMode';

  final TokenStore _tokenStore;
  final FlutterSecureStorage _settings;
  final LocalStore? _localStore;
  final http.Client? _httpClient;
  ApiClient? _client;
  late PosApi pos;
  late SalesApi sales;
  late ReportsApi reports;
  late SyncApi sync;
  Future<void>? _deviceRegistration;

  String? _username;
  List<String> _roles = const [];
  String _baseUrl = kDefaultApiBaseUrl;
  ThemeMode _themeMode = ThemeMode.system;
  bool _restored = false;

  bool get isRestored => _restored;
  bool get isSignedIn => _username != null;
  String? get username => _username;
  List<String> get roles => _roles;
  bool get isAdmin => _roles.contains('ADMIN');

  /// ADMIN and MANAGER may create and edit products and receive stock. The
  /// server enforces the real permissions; this only hides what would be refused.
  bool get canManageProducts =>
      _roles.contains('ADMIN') || _roles.contains('MANAGER');
  String get baseUrl => _baseUrl;
  ThemeMode get themeMode => _themeMode;

  /// Loads a saved token and API base URL at startup.
  Future<void> restore() async {
    final savedUrl = await _settings.read(key: _baseUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _baseUrl = savedUrl;
      _rebuildServices();
    }
    _themeMode = ThemeMode.values.asNameMap()[await _settings.read(key: _themeModeKey)] ??
        ThemeMode.system;
    _username = await _tokenStore.readUsername();
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) _username = null;
    _restored = true;
    _registerDeviceLater();
    notifyListeners();
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final AuthResponse auth = await pos.login(
      username: username,
      password: password,
    );
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
    _registerDeviceLater();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _tokenStore.clear();
    _username = null;
    _roles = const [];
    notifyListeners();
  }

  /// Switches the app between light, dark and the phone's setting. The change
  /// applies immediately; saving it for the next launch is best effort.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      await _settings.write(key: _themeModeKey, value: mode.name);
    } catch (_) {
      // Not persisted (e.g. storage unavailable); the choice still holds for this run.
    }
  }

  /// Saves a new API base URL and reconnects the services.
  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _settings.write(key: _baseUrlKey, value: trimmed);
    _baseUrl = trimmed;
    _rebuildServices();
    _registerDeviceLater();
    notifyListeners();
  }

  /// The in-flight device registration, so tests can await it.
  @visibleForTesting
  Future<void>? get deviceRegistration => _deviceRegistration;

  /// Registers this till with the server, without blocking the caller. A
  /// failure is quietly retried on the next sign-in, restore or URL change —
  /// nothing else depends on it yet.
  void _registerDeviceLater() {
    final store = _localStore;
    if (store == null || _username == null) return;
    _deviceRegistration = DeviceIdentity(store.meta)
        .ensureRegistered(
          sync,
          baseUrl: _baseUrl,
          name: 'Kantemba till',
          model: Platform.operatingSystem,
          appVersion: kAppVersion,
        )
        .then((_) {});
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
      httpClient: _httpClient,
    );
    _client = client;
    pos = PosApi(client);
    sales = SalesApi(client);
    reports = ReportsApi(client);
    sync = SyncApi(client);
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
