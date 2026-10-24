import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Centered progress indicator for a screen's first load.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: Gap.lg),
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A centered message with an icon and optional action, for empty lists and for
/// failed loads. Scrolls, so it also works inside a pull-to-refresh and when the
/// keyboard or a large text size leaves little room.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.error = false,
  });

  /// Something went wrong loading: shows a retry action and error colours.
  const StateView.error({
    Key? key,
    required String message,
    required VoidCallback onRetry,
  }) : this(
         key: key,
         icon: Icons.cloud_off_outlined,
         title: 'Something went wrong',
         message: message,
         actionLabel: 'Try again',
         onAction: onRetry,
         error: true,
       );

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: error
                          ? scheme.errorContainer
                          : scheme.secondaryContainer,
                      foregroundColor: error
                          ? scheme.onErrorContainer
                          : scheme.onSecondaryContainer,
                      child: Icon(icon, size: 30),
                    ),
                    const SizedBox(height: Gap.lg),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (onAction != null && actionLabel != null) ...[
                      const SizedBox(height: Gap.lg),
                      error
                          ? OutlinedButton.icon(
                              onPressed: onAction,
                              icon: const Icon(Icons.refresh),
                              label: Text(actionLabel!),
                            )
                          : FilledButton(
                              onPressed: onAction,
                              child: Text(actionLabel!),
                            ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
