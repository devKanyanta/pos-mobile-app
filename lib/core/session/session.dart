import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../data/local/local_store.dart';
import '../../data/models/auth_models.dart';
import '../../data/models/catalog_models.dart';
import '../../data/services/pos_api.dart';
import '../../data/services/reports_api.dart';
import '../../data/services/sales_api.dart';
import '../../data/services/sync_api.dart';
import '../api/api_client.dart';
import '../api/token_store.dart';
import '../checkout/product_lookup.dart';
import '../sync/catalog_repository.dart';
import '../sync/catalog_sync.dart';
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
    this.catalogSyncInterval = const Duration(minutes: 5),
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
  CatalogRepository? _catalog;
  CatalogSync? _catalogSync;
  Future<void>? _deviceRegistration;
  Future<bool>? _initialCatalogSync;
  Timer? _catalogTimer;

  /// How often the catalogue is refreshed while signed in; null turns the
  /// periodic refresh off (the pull after sign-in still happens).
  final Duration? catalogSyncInterval;

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
    _startSync();
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
    _startSync();
    notifyListeners();
  }

  Future<void> signOut() async {
    _stopSync();
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
    final changed = trimmed != _baseUrl;
    _baseUrl = trimmed;
    _rebuildServices();
    // A bookmark from another server would hide products this one has.
    if (changed) await _catalogSync?.reset();
    _startSync();
    notifyListeners();
  }

  /// The in-flight device registration, so tests can await it.
  @visibleForTesting
  Future<void>? get deviceRegistration => _deviceRegistration;

  /// The catalogue pull that follows registration, so tests can await it.
  @visibleForTesting
  Future<bool>? get initialCatalogSync => _initialCatalogSync;

  /// Products and payment methods for checkout: the server's live answer,
  /// or the cached catalogue when the server cannot be reached.
  ProductLookup get productLookup => _catalog ?? pos;

  Future<List<PaymentMethod>> loadPaymentMethods() =>
      _catalog?.paymentMethods() ?? pos.listPaymentMethods();

  Future<List<Product>> loadAllProducts() =>
      _catalog?.allProducts() ?? pos.listProducts();

  /// Registers this till, pulls the catalogue, and keeps pulling it on a
  /// timer — all without blocking the caller. Failures are quietly retried
  /// at the next sign-in, restore, URL change or timer tick; nothing waits
  /// on them.
  void _startSync() {
    _catalogTimer?.cancel();
    final store = _localStore;
    final catalogSync = _catalogSync;
    if (store == null || catalogSync == null || _username == null) return;

    _deviceRegistration = DeviceIdentity(store.meta)
        .ensureRegistered(
          sync,
          baseUrl: _baseUrl,
          name: 'Kantemba till',
          model: Platform.operatingSystem,
          appVersion: kAppVersion,
        )
        .then((_) {});
    _initialCatalogSync = _deviceRegistration!.then((_) => catalogSync.sync());

    final interval = catalogSyncInterval;
    if (interval != null) {
      _catalogTimer = Timer.periodic(interval, (_) => catalogSync.sync());
    }
  }

  void _stopSync() {
    _catalogTimer?.cancel();
    _catalogTimer = null;
  }

  void _handleUnauthorized() {
    if (_username == null) return;
    _stopSync();
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
    final store = _localStore;
    if (store != null) {
      _catalog = CatalogRepository(pos: pos, cache: store.catalog);
      _catalogSync = CatalogSync(
        api: sync,
        cache: store.catalog,
        meta: store.meta,
      );
    }
  }

  @override
  void dispose() {
    _stopSync();
    _client?.close();
    super.dispose();
  }
}
