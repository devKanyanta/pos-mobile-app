import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/session/session_scope.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/busy_button.dart';
import 'widgets/notice_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    if (_saving) return;
    final session = SessionScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await session.setBaseUrl(_url.text);
      NoticeBar.success(messenger, 'API address saved');
    } on ApiException catch (e) {
      NoticeBar.error(messenger, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final session = SessionScope.of(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to keep selling.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout,
    );
    if (ok) await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = SessionScope.of(context);
    if (!_seeded) {
      _url.text = session.baseUrl;
      _seeded = true;
    }
    final username = session.username ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.xs,
              ),
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(username.isEmpty ? '?' : username[0].toUpperCase()),
              ),
              title: Text(username.isEmpty ? 'Signed in' : username),
              subtitle: const Text('Signed in'),
            ),
          ),
          const SizedBox(height: Gap.xl),
          Text(
            'Appearance',
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: Gap.sm),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
              ],
              selected: {session.themeMode},
              onSelectionChanged: (modes) => session.setThemeMode(modes.single),
            ),
          ),
          const SizedBox(height: Gap.xl),
          Text(
            'Server',
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _url,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              helperText: 'e.g. http://10.0.2.2:8081/api/v1',
            ),
            onSubmitted: (_) => _saveUrl(),
          ),
          const SizedBox(height: Gap.md),
          BusyButton(
            label: _saving ? 'Saving…' : 'Save address',
            busy: _saving,
            expand: true,
            onPressed: _saveUrl,
          ),
          const SizedBox(height: Gap.xl),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }
}
