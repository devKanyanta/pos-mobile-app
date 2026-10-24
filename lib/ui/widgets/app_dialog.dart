import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'busy_button.dart';

/// The one dialog layout: a title, an optional description, scrollable content
/// and a consistent action row (secondary action left of the primary one).
///
/// * Content scrolls, so long forms and large text sizes never overflow, and the
///   dialog resizes above the keyboard so the actions stay reachable.
/// * While [busy] the dialog cannot be dismissed by back/tap-outside, so a request
///   in flight is never orphaned.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.children = const [],
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel = 'Cancel',
    this.onSecondary,
    this.busy = false,
    this.destructive = false,
    this.extraActions = const [],
    this.hideSecondary = false,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final List<Widget> children;

  /// Null for dialogs that only offer secondary choices (e.g. a cashier's view).
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  final String secondaryLabel;

  /// Defaults to closing the dialog with no result.
  final VoidCallback? onSecondary;
  final bool busy;
  final bool destructive;

  /// Additional text buttons placed before the secondary action.
  final List<Widget> extraActions;

  /// For acknowledgements that have a single button.
  final bool hideSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        scrollable: true,
        icon: icon == null
            ? null
            : Icon(icon, color: destructive ? scheme.error : scheme.primary),
        iconPadding: const EdgeInsets.only(top: Gap.xl),
        titlePadding: EdgeInsets.fromLTRB(
          Gap.xl,
          icon == null ? Gap.xl : Gap.md,
          Gap.xl,
          Gap.sm,
        ),
        contentPadding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
        actionsPadding: const EdgeInsets.fromLTRB(
          Gap.lg,
          Gap.sm,
          Gap.lg,
          Gap.lg,
        ),
        title: Text(
          title,
          textAlign: icon == null ? TextAlign.start : TextAlign.center,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description != null)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: children.isEmpty ? 0 : Gap.lg,
                  ),
                  child: Text(
                    description!,
                    textAlign: icon == null
                        ? TextAlign.start
                        : TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: Gap.md),
                children[i],
              ],
            ],
          ),
        ),
        actionsOverflowButtonSpacing: Gap.sm,
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          ...extraActions,
          if (!hideSecondary)
            TextButton(
              onPressed: busy
                  ? null
                  : (onSecondary ?? () => Navigator.pop(context)),
              child: Text(secondaryLabel),
            ),
          if (primaryLabel != null)
            BusyButton(
              label: primaryLabel!,
              onPressed: onPrimary,
              busy: busy,
              destructive: destructive,
            ),
        ],
      ),
    );
  }
}

/// Asks the user to confirm an action. Returns false when dismissed.
///
/// Set [destructive] for anything that removes or reverses data (void, refund,
/// sign out): the confirm button turns red and the wording should name the effect.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      description: message,
      icon: icon,
      destructive: destructive,
      primaryLabel: confirmLabel,
      secondaryLabel: cancelLabel,
      onPrimary: () => Navigator.pop(context, true),
      onSecondary: () => Navigator.pop(context, false),
    ),
  );
  return result ?? false;
}
