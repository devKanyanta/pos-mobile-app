import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Transient confirmations and failures shown as a floating snackbar.
///
/// Takes a [ScaffoldMessengerState] (not a [BuildContext]) so callers can grab
/// it before an `await` and still show the result after the screen has moved on.
/// Each call replaces the previous notice, so rapid actions never stack them.
abstract final class NoticeBar {
  static void success(ScaffoldMessengerState messenger, String message) =>
      _show(messenger, message, Icons.check_circle_outline, error: false);

  static void error(ScaffoldMessengerState messenger, String message) =>
      _show(messenger, message, Icons.error_outline, error: true);

  static void info(ScaffoldMessengerState messenger, String message) =>
      _show(messenger, message, Icons.info_outline, error: false);

  static void _show(
    ScaffoldMessengerState messenger,
    String message,
    IconData icon, {
    required bool error,
  }) {
    final scheme = Theme.of(messenger.context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Errors stay long enough to read; confirmations get out of the way.
          duration: Duration(seconds: error ? 6 : 3),
          showCloseIcon: error,
          closeIconColor: scheme.onInverseSurface,
          content: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: error ? scheme.errorContainer : scheme.inversePrimary,
              ),
              const SizedBox(width: Gap.md),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
