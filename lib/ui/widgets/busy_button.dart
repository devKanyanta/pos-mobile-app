import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A [FilledButton] that cannot be pressed twice: while [busy] it is disabled and
/// shows a spinner in place of the icon. The label stays visible (callers pass the
/// in-progress wording, e.g. "Saving…") so the button never changes width or meaning.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.destructive = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  /// Red styling for actions that remove or reverse something.
  final bool destructive;

  /// Fill the available width (full-width form and checkout actions).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget? leading = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          )
        : icon == null
        ? null
        : Icon(icon, size: 20);

    final style = destructive
        ? FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          )
        : null;
    final onTap = busy ? null : onPressed;
    final button = leading == null
        ? FilledButton(onPressed: onTap, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onTap,
            style: style,
            icon: leading,
            label: Text(label),
          );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A small inline spinner for field suffixes and list rows.
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: SizedBox.square(
      dimension: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}
