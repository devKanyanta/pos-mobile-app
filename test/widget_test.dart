import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/ui/login_screen.dart';

void main() {
  testWidgets('login screen renders username, password and sign in', (
    WidgetTester tester,
  ) async {
    final session = Session();
    await tester.pumpWidget(
      SessionScope(
        session: session,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('Kantemba POS'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
