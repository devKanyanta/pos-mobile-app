import 'package:flutter/material.dart';

import 'core/session/session.dart';
import 'core/session/session_scope.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

void main() {
  runApp(const KantembaApp());
}

class KantembaApp extends StatefulWidget {
  const KantembaApp({super.key});

  @override
  State<KantembaApp> createState() => _KantembaAppState();
}

class _KantembaAppState extends State<KantembaApp> {
  final Session _session = Session();

  @override
  void initState() {
    super.initState();
    _session.restore();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: _session,
      child: MaterialApp(
        title: 'Kantemba POS',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: ListenableBuilder(
          listenable: _session,
          builder: (context, _) {
            if (!_session.isRestored) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return _session.isSignedIn ? const HomeShell() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
