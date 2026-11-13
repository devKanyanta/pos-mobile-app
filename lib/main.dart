import 'package:flutter/material.dart';

import 'core/session/session.dart';
import 'core/session/session_scope.dart';
import 'core/sync/connectivity.dart';
import 'data/local/local_store.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/state_views.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localStore = await LocalStore.open();
  runApp(KantembaApp(localStore: localStore));
}

class KantembaApp extends StatefulWidget {
  const KantembaApp({super.key, this.localStore});

  /// The offline database; null (in tests) runs the app online-only.
  final LocalStore? localStore;

  @override
  State<KantembaApp> createState() => _KantembaAppState();
}

class _KantembaAppState extends State<KantembaApp> {
  late final Session _session = Session(
    localStore: widget.localStore,
    connectivity: widget.localStore == null ? null : deviceConnectivity(),
  );

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
