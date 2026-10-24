import 'package:flutter/material.dart';

import 'core/session/session.dart';
import 'core/session/session_scope.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/state_views.dart';

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
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, _) => MaterialApp(
          title: 'Kantemba POS',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _session.themeMode,
          home: !_session.isRestored
              ? const Scaffold(body: LoadingView())
              : _session.isSignedIn
                  ? const HomeShell()
                  : const LoginScreen(),
        ),
      ),
    );
  }
}
