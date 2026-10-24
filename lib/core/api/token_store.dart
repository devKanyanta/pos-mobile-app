import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the bearer token in the platform secure store (Android Keystore).
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'kantemba.jwt';
  static const _usernameKey = 'kantemba.username';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<String?> readUsername() => _storage.read(key: _usernameKey);

  Future<void> save({required String token, required String username}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _usernameKey, value: username);
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _usernameKey);
  }
}
