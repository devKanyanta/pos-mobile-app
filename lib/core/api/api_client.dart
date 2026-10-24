import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin JSON client for the POS backend. Attaches the bearer token, decodes
/// responses and maps failures to [ApiException].
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    this.onUnauthorized,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client();

  /// e.g. http://10.0.2.2:8081/api/v1 (Android emulator to host machine).
  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  /// Called when a protected request returns 401 so the session can be cleared.
  final void Function()? onUnauthorized;
  final Duration timeout;
  final http.Client _http;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) => _send('POST', path, body: body, query: query);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<void> delete(String path) => _send('DELETE', path);

  /// Fetches a non-JSON resource (CSV, PDF, plain text) as raw bytes.
  Future<List<int>> getBytes(String path, {Map<String, String>? query}) async {
    final response = await _execute('GET', path, query: query, auth: true);
    return response.bodyBytes;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final response = await _execute(
      method,
      path,
      body: body,
      query: query,
      auth: auth,
    );
    if (response.bodyBytes.isEmpty) return null;
    final text = utf8.decode(response.bodyBytes);
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      throw ApiException(
        'Unexpected response from server.',
        status: response.statusCode,
        path: path,
      );
    }
  }

  Future<http.Response> _execute(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final uri = _uri(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    if (auth) {
      final token = await tokenProvider();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(
        'The server took too long to respond. Check your connection.',
        path: path,
      );
    } on Exception {
      throw ApiException(
        'Cannot reach the server. Check your connection and the server address.',
        path: path,
      );
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;

    if (status == 401 && auth) onUnauthorized?.call();
    throw _errorFrom(response, path);
  }

  Uri _uri(String path, Map<String, String>? query) {
    final base = Uri.parse(baseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$basePath$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  ApiException _errorFrom(http.Response response, String path) {
    String? message;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } on Exception {
      // Fall through to the generic message below.
    }
    message ??= _defaultMessage(response.statusCode);
    return ApiException(message, status: response.statusCode, path: path);
  }

  String _defaultMessage(int status) {
    switch (status) {
      case 400:
        return 'The request was not valid.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do this.';
      case 404:
        return 'The requested item was not found.';
      case 409:
        return 'This conflicts with existing data.';
      case 413:
        return 'The file is too large.';
      case 503:
        return 'This service is not available right now.';
      default:
        return 'Something went wrong on the server ($status).';
    }
  }

  void close() => _http.close();
}
