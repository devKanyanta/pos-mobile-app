import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/ui/checkout_screen.dart';
import 'package:kantemba/ui/login_screen.dart';
import 'package:kantemba/ui/product_actions.dart';
import 'package:kantemba/ui/product_form_screen.dart';
import 'package:kantemba/ui/settings_screen.dart';
import 'package:kantemba/ui/theme/app_theme.dart';
import 'package:kantemba/ui/widgets/app_dialog.dart';
import 'package:kantemba/ui/widgets/app_sheet.dart';
import 'package:kantemba/ui/widgets/state_views.dart';
import 'package:kantemba/ui/widgets/status_banner.dart';

import 'support/fake_server.dart';

const double _width = 320;
const double _height = 568;
const double _keyboard = 216;

/// A small phone (320 x 568) so overflow problems show up. Any RenderFlex overflow
/// throws during the test, so "no exception" is the assertion for layout.
void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(_width, _height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The app's real theme, with the user's largest text size and the keyboard open.
Widget _app(Widget home, {double textScale = 2.0, double keyboard = 0}) =>
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        );
      },
      home: home,
    );

Widget _opener(Future<Object?> Function(BuildContext) open) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  _themeTests();
  group('AppDialog', () {
    testWidgets(
      'long content scrolls and the actions stay reachable above the keyboard',
      (tester) async {
        _smallPhone(tester);
        await tester.pumpWidget(
          _app(
            _opener(
              (context) => showDialog<void>(
                context: context,
                builder: (_) => AppDialog(
                  title: 'A fairly long dialog title that wraps',
                  description:
                      'Supporting text that explains what this dialog does. ' *
                      3,
                  primaryLabel: 'Save changes',
                  onPrimary: () {},
                  children: [
                    for (var i = 0; i < 6; i++)
                      TextField(
                        decoration: InputDecoration(labelText: 'Field $i'),
                      ),
                  ],
                ),
              ),
            ),
            keyboard: _keyboard,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final save = tester.getRect(find.text('Save changes'));
        expect(save.bottom, lessThanOrEqualTo(_height - _keyboard));
        expect(save.left, greaterThanOrEqualTo(0));
        expect(save.right, lessThanOrEqualTo(_width));
      },
    );

    testWidgets(
      'confirm returns true on confirm and false on cancel or dismissal',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          _app(
            _opener(
              (context) async => result = await showConfirmDialog(
                context,
                title: 'Void sale?',
                message: 'This cannot be undone.',
                confirmLabel: 'Void sale',
                destructive: true,
              ),
            ),
            textScale: 1,
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('This cannot be undone.'), findsOneWidget);
        await tester.tap(find.text('Void sale'));
        await tester.pumpAndSettle();
        expect(result, isTrue);

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(result, isFalse);

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(2, 2)); // the scrim
        await tester.pumpAndSettle();
        expect(result, isFalse);
      },
    );

    testWidgets(
      'a busy dialog cannot be dismissed and its primary button is disabled',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          _app(
            _opener(
              (context) => showDialog<void>(
                context: context,
                builder: (_) => AppDialog(
                  title: 'Saving',
                  busy: true,
                  primaryLabel: 'Saving…',
                  onPrimary: () => presses++,
                ),
              ),
            ),
            textScale: 1,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.text('Saving…'), warnIfMissed: false);
        await tester.tap(find.text('Cancel'), warnIfMissed: false);
        await tester.tapAt(const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 400));

        expect(presses, 0);
        expect(find.text('Saving'), findsOneWidget, reason: 'still open');
      },
    );
  });

  group('AppSheet', () {
    testWidgets(
      'many actions scroll on a small phone at the largest text size',
      (tester) async {
        _smallPhone(tester);
        await tester.pumpWidget(
          _app(
            _opener(
              (context) => showAppSheet<void>(
                context,
                title: 'Choose a product',
                subtitle: '30 products match',
                children: [
                  for (var i = 0; i < 30; i++)
                    SheetAction(
                      icon: Icons.inventory_2_outlined,
                      title: 'A product with quite a long name number $i',
                      subtitle: '10.00',
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Choose a product'), findsOneWidget);
      },
    );
  });

  group('state views', () {
    testWidgets('the error state offers a working retry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: StateView.error(
              message: 'Cannot reach the server.',
              onRetry: () => retries++,
            ),
          ),
          textScale: 1,
        ),
      );
      expect(find.text('Cannot reach the server.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('a banner action fires and long text wraps without overflow', (
      tester,
    ) async {
      _smallPhone(tester);
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: StatusBanner(
              'Payment not confirmed: the connection dropped while sending. ' *
                  3,
              kind: BannerKind.warning,
              actionLabel: 'Retry',
              onAction: () => taps++,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Retry'));
      expect(taps, 1);
    });
  });

  group('forms and flows', () {
    testWidgets(
      'a failed stock adjustment keeps the dialog open and the typed values',
      (tester) async {
        final server = FakeServer(role: 'MANAGER')
          ..adjustmentError = 'Stock cannot be negative';
        final session = await server.signedInSession();
        final product = Product.fromJson(
          productJson(1, '6001', name: 'Milk', stock: 5),
        );
        await tester.pumpWidget(
          SessionScope(
            session: session,
            child: _app(
              _opener((context) => showAdjustmentDialog(context, product)),
              textScale: 1,
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Change (use - to reduce)'),
          '-2',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Damaged',
        );
        await tester.tap(find.text('Save adjustment'));
        await tester.pumpAndSettle();

        expect(find.text('Stock cannot be negative'), findsOneWidget);
        expect(
          find.text('-2'),
          findsOneWidget,
          reason: 'typed values are preserved',
        );
        expect(find.text('Damaged'), findsOneWidget);
        expect(
          find.text('Save adjustment'),
          findsOneWidget,
          reason: 'can retry',
        );

        // The user retries once the problem is gone.
        server.adjustmentError = null;
        await tester.tap(find.text('Save adjustment'));
        await tester.pumpAndSettle();
        expect(find.text('Stock cannot be negative'), findsNothing);
        expect(
          find.text('Save adjustment'),
          findsNothing,
          reason: 'dialog closed on success',
        );
        expect(find.textContaining('Adjusted Milk by -2'), findsOneWidget);
      },
    );

    testWidgets('pressing save twice sends one adjustment', (tester) async {
      final server = FakeServer(role: 'MANAGER');
      final session = await server.signedInSession();
      final product = Product.fromJson(
        productJson(1, '6001', name: 'Milk', stock: 5),
      );
      await tester.pumpWidget(
        SessionScope(
          session: session,
          child: _app(
            _opener((context) => showAdjustmentDialog(context, product)),
            textScale: 1,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Change (use - to reduce)'),
        '1',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Count');

      await tester.tap(find.text('Save adjustment'));
      await tester.tap(find.text('Save adjustment'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(server.posts('/inventory-movements/adjustment').length, 1);
    });

    testWidgets('the adjustment dialog previews the resulting stock level', (
      tester,
    ) async {
      final server = FakeServer(role: 'MANAGER');
      final session = await server.signedInSession();
      final product = Product.fromJson(
        productJson(1, '6001', name: 'Milk', stock: 5),
      );
      await tester.pumpWidget(
        SessionScope(
          session: session,
          child: _app(
            _opener((context) => showAdjustmentDialog(context, product)),
            textScale: 1,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Change (use - to reduce)'),
        '-2',
      );
      await tester.pump();
      expect(find.text('New stock level: 3'), findsOneWidget);
    });

    testWidgets(
      'login fits a small phone at the largest text size with the keyboard open',
      (tester) async {
        _smallPhone(tester);
        await tester.pumpWidget(
          SessionScope(
            session: Session(),
            child: _app(const LoginScreen(), keyboard: _keyboard),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Sign in'), findsOneWidget);
      },
    );

    testWidgets('login explains missing fields instead of calling the server', (
      tester,
    ) async {
      await tester.pumpWidget(
        SessionScope(
          session: Session(),
          child: _app(const LoginScreen(), textScale: 1),
        ),
      );
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Enter your username and password.'), findsOneWidget);
    });

    testWidgets(
      'the product form fits a small phone and Save stays above the keyboard',
      (tester) async {
        _smallPhone(tester);
        final server = FakeServer(role: 'MANAGER');
        final session = await server.signedInSession();
        await tester.pumpWidget(
          SessionScope(
            session: session,
            child: _app(const ProductFormScreen(), keyboard: _keyboard),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.text('Save')).bottom,
          lessThanOrEqualTo(_height - _keyboard),
        );
      },
    );

    testWidgets(
      'checkout fits a small phone at the largest text size with items in the cart',
      (tester) async {
        _smallPhone(tester);
        final server = FakeServer()
          ..products['6001'] = productJson(
            1,
            '6001',
            name: 'Extra long product name for the family size pack',
            price: 10,
            stock: 30,
          );
        final session = await server.signedInSession();
        await tester.pumpWidget(
          SessionScope(
            session: session,
            child: _app(const CheckoutScreen(active: false)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, '6001');
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Extra long product name'), findsWidgets);
      },
    );

    testWidgets('clearing a sale asks for confirmation first', (tester) async {
      final server = FakeServer()
        ..products['6001'] = productJson(1, '6001', name: 'Milk', stock: 3);
      final session = await server.signedInSession();
      await tester.pumpWidget(
        SessionScope(
          session: session,
          child: _app(const CheckoutScreen(active: false), textScale: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear sale'));
      await tester.pumpAndSettle();
      expect(find.text('Clear this sale?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.text('Milk'),
        findsOneWidget,
        reason: 'cancel keeps the cart',
      );

      await tester.tap(find.byTooltip('Clear sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear sale'));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);
      expect(
        find.text('No items yet. Scan a product to start.'),
        findsOneWidget,
      );
    });
  });
}

void _themeTests() {
  testWidgets('the appearance setting switches the theme and is remembered', (tester) async {
    final session = Session();
    await tester.pumpWidget(SessionScope(
      session: session,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: session.themeMode,
          home: const SettingsScreen(),
        ),
      ),
    ));
    Brightness current() => Theme.of(tester.element(find.byType(SettingsScreen))).brightness;
    expect(session.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(session.themeMode, ThemeMode.dark);
    expect(current(), Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(current(), Brightness.light);
  });
}
