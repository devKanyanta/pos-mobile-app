import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BannerKind { error, warning, success, info }

/// An inline message tied to the content it describes (a form, a scan result).
///
/// Colours come from the [ColorScheme] roles so the banner reads correctly in
/// light and dark. Use [NoticeBar] (snackbars) for transient confirmations and
/// this for messages the user must be able to re-read while fixing something.
class StatusBanner extends StatelessWidget {
  const StatusBanner(
    this.message, {
    super.key,
    this.kind = BannerKind.info,
    this.actionLabel,
    this.onAction,
    this.margin,
  });

  const StatusBanner.error(
    String message, {
    Key? key,
    String? actionLabel,
    VoidCallback? onAction,
    EdgeInsetsGeometry? margin,
  }) : this(
         message,
         key: key,
         kind: BannerKind.error,
         actionLabel: actionLabel,
         onAction: onAction,
         margin: margin,
       );

  final String message;
  final BannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (kind) {
      BannerKind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      BannerKind.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      BannerKind.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      BannerKind.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm + 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: foreground),
            ),
            const SizedBox(width: Gap.sm + 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: foreground),
                ),
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
