import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final session = SessionScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.setBaseUrl(_url.text);
      messenger.showSnackBar(const SnackBar(content: Text('API address saved')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (!_seeded) {
      _url.text = session.baseUrl;
      _seeded = true;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Signed in as ${session.username ?? ''}'),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              helperText: 'e.g. http://10.0.2.2:8081/api/v1',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saveUrl, child: const Text('Save address')),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: session.signOut,
          ),
        ],
      ),
    );
  }
}
