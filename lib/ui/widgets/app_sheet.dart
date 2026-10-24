import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows a modal bottom sheet with the shared header (title + optional subtitle)
/// and a scrollable body. Use it for choices and action menus, which are more
/// natural as a thumb-reachable sheet than as a dialog.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Widget> children,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        AppSheet(title: title, subtitle: subtitle, children: children),
  );
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: Gap.xs, bottom: Gap.md),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable row for an [AppSheet]: leading icon in a tonal circle, title, optional
/// supporting text. At least 56 px tall so it is an easy touch target.
class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      leading: icon == null
          ? null
          : CircleAvatar(
              radius: 20,
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: Icon(icon, size: 20),
            ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
