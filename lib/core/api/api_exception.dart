/// Error raised by the API layer. [status] is null for network failures.
class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.path});

  final String message;
  final int? status;
  final String? path;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}
