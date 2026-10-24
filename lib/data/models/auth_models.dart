import 'json_utils.dart';

/// `AuthResponse` from `POST /auth/login` and `POST /auth/register`.
class AuthResponse {
  const AuthResponse({
    required this.token,
    required this.username,
    required this.roles,
  });

  final String token;
  final String username;
  final List<String> roles;

  bool get isAdmin => roles.contains('ADMIN');

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        token: toStr(json['token']),
        username: toStr(json['username']),
        roles: (json['roles'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );
}
