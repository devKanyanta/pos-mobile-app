import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:kantemba/core/receipt/receipt_data.dart';
import 'package:kantemba/core/receipt/receipt_output.dart';
import 'package:kantemba/core/receipt/receipt_pdf.dart';
import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/data/models/merchant_models.dart';
import 'package:kantemba/data/models/receipt_models.dart';
import 'package:kantemba/data/models/sale_models.dart';
import 'package:kantemba/ui/checkout_screen.dart';
import 'package:kantemba/ui/receipt_dialog.dart';
import 'package:kantemba/ui/theme/app_theme.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _saleJson({String paymentStatus = 'PAID', double change = 8.4}) => {
  'id': 7,
  'saleNumber': 'S-0007',
  'customerName': 'Mary Banda',
  'customerPhone': '0977123456',
  'subtotal': 30.0,
  'discountAmount': 2.0,
  'vatAmount': 4.48,
  'totalAmount': 32.48,
  'amountPaid': paymentStatus == 'PAID' ? 32.48 : 10.0,
  'balanceDue': paymentStatus == 'PAID' ? 0.0 : 22.48,
  'changeGiven': change,
  'paymentStatus': paymentStatus,
  'saleStatus': 'ACTIVE',
  'createdBy': 'cashier1',
  'soldAt': '2026-10-24T10:30:00',
  'items': [
    {
      'id': 1,
      'productId': 1,
      'productName': 'Fresh Milk 1L',
      'quantity': 2,
      'unitPrice': 10.0,
      'lineTotal': 20.0,
      'totalAmount': 23.2,
      'vatRate': 16.0,
      'vatAmount': 3.2,
    },
    {
      'id': 2,
      'productId': 2,
      'productName': 'Brown Bread',
      'quantity': 1,
      'unitPrice': 12.0,
      'lineTotal': 12.0,
      'totalAmount': 13.92,
      'vatRate': 16.0,
      'vatAmount': 1.92,
      'discountAmount': 2.0,
    },
  ],
  'payments': [
    {
      'id': 1,
      'paymentMethodName': 'Cash',
      'paymentMethodType': 'CASH',
      'amount': 32.48,
      'amountTendered': 40.88,
      'changeAmount': change,
    },
  ],
};

const _merchantJson = {
  'accountId': 'a1',
  'businessName': 'Mapalo General Dealers',
  'tpin': '1002003004',
  'phone': '0211123456',
  'email': 'shop@example.com',
  'address': 'Plot 12, Cairo Road, Lusaka',
  'receiptFooter': 'Goods once sold are not returnable.',
  'plan': 'MICRO',
  'features': <String, dynamic>{},
};

const _fiscalJson = {
  'receiptNumber': 'R-0007',
  'zraStatus': 'SUCCESS',
  'zraVerified': true,
  'zraInvoiceNo': 4521,
  'zraReceiptNo': 4400,
  'zraReceiptSignature': 'ABCD-1234-EFGH',
  'zraSdcId': 'SDC0010001',
  'zraMrcNo': 'MRC-77',
  'zraQrCodeUrl': 'https://example.com/verify/ABCD',
  'zraReceiptDate': '2026-10-24 10:30',
};

/// Records what the user asked the receipt to do instead of opening real printer UI.
class _FakeOutput extends ReceiptOutput {
  _FakeOutput({this.failWith});

  final List<ReceiptData> printed = [];
  final List<ReceiptData> saved = [];
  final Object? failWith;

  @override
  Future<void> print(ReceiptData data) async {
    if (failWith != null) throw failWith!;
    printed.add(data);
  }

  @override
  Future<void> savePdf(ReceiptData data) async {
    if (failWith != null) throw failWith!;
    saved.add(data);
  }
}

Future<void> _openReceipt(
  WidgetTester tester,
  FakeServer server, {
  required ReceiptOutput output,
  Map<String, dynamic>? sale,
  double textScale = 1,
}) async {
  final session = await server.signedInSession();
  final model = Sale.fromJson(sale ?? _saleJson());
  await tester.pumpWidget(SessionScope(
    session: session,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showReceiptDialog(context, model, output: output),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('receipt dialog', () {
    testWidgets('shows the business, the items, the tax, the payments and the fiscal details',
        (tester) async {
      final server = FakeServer()
        ..merchant = _merchantJson
        ..receipt = _fiscalJson;
      await _openReceipt(tester, server, output: _FakeOutput());

      expect(find.text('Sale complete'), findsOneWidget);
      expect(find.text('Sale S-0007'), findsOneWidget);
      expect(find.text('Mapalo General Dealers'), findsOneWidget);
      expect(find.text('Plot 12, Cairo Road, Lusaka'), findsOneWidget);
      expect(find.text('TPIN: 1002003004'), findsOneWidget);
      expect(find.text('R-0007'), findsOneWidget, reason: 'the server receipt number');
      expect(find.text('cashier1'), findsOneWidget);
      expect(find.text('Mary Banda'), findsOneWidget);
      expect(find.text('Fresh Milk 1L'), findsOneWidget);
      expect(find.textContaining('2 × 10.00 · VAT 16%'), findsOneWidget);
      expect(find.text('Discount -2.00'), findsWidgets);
      expect(find.text('4.48'), findsOneWidget, reason: 'total VAT');
      expect(find.text('Total 32.48'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Change 8.40'), findsOneWidget);
      expect(find.text('ZRA fiscal invoice'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('ABCD-1234-EFGH'), findsOneWidget);
      expect(find.text('Goods once sold are not returnable.'), findsOneWidget);
    });

    testWidgets('is still a complete receipt when the business and fiscal details cannot load',
        (tester) async {
      final server = FakeServer(); // /merchant and /receipts answer 404
      await _openReceipt(tester, server, output: _FakeOutput());

      expect(find.text('Kantemba POS'), findsOneWidget);
      expect(find.text('Total 32.48'), findsOneWidget);
      expect(find.text('Fresh Milk 1L'), findsOneWidget);
      expect(find.text('ZRA fiscal invoice'), findsNothing);
      expect(find.text('Thank you for your purchase.'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'loading finished');
    });

    testWidgets('an unpaid sale shows the balance due and is titled as recorded', (tester) async {
      final server = FakeServer();
      await _openReceipt(
        tester,
        server,
        output: _FakeOutput(),
        sale: _saleJson(paymentStatus: 'PARTIAL', change: 0),
      );
      expect(find.text('Sale recorded'), findsOneWidget);
      expect(find.text('Balance due 22.48'), findsOneWidget);
      expect(find.textContaining('Change'), findsNothing);
    });

    testWidgets('Print and Save PDF hand the full receipt, including loaded details, to the output',
        (tester) async {
      final server = FakeServer()
        ..merchant = _merchantJson
        ..receipt = _fiscalJson;
      final output = _FakeOutput();
      await _openReceipt(tester, server, output: output);

      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();

      expect(output.printed.length, 1);
      expect(output.saved.length, 1);
      expect(output.printed.single.businessName, 'Mapalo General Dealers');
      expect(output.saved.single.receiptNumber, 'R-0007');
      expect(output.saved.single.fileName, 'receipt-R-0007.pdf');
    });

    testWidgets('a printing failure is explained and the buttons work again', (tester) async {
      final server = FakeServer();
      await _openReceipt(tester, server, output: _FakeOutput(failWith: 'no printer found'));

      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not print the receipt'), findsOneWidget);
      expect(find.textContaining('no printer found'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Print')).onPressed,
          isNotNull);
    });

    testWidgets('fits a small phone at the largest text size', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final server = FakeServer()
        ..merchant = _merchantJson
        ..receipt = _fiscalJson;
      await _openReceipt(tester, server, output: _FakeOutput(), textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.text('New sale'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
    });

    testWidgets('the done button closes the receipt', (tester) async {
      await _openReceipt(tester, FakeServer(), output: _FakeOutput());
      await tester.tap(find.text('New sale'));
      await tester.pumpAndSettle();
      expect(find.text('Sale complete'), findsNothing);
    });
  });

  group('receipt PDF', () {
    ReceiptData data({bool fiscal = true, bool empty = false}) {
      final json = _saleJson();
      if (empty) json['items'] = <Object>[];
      return ReceiptData(
        sale: Sale.fromJson(json),
        merchant: MerchantProfile.fromJson(_merchantJson),
        fiscal: fiscal ? ReceiptInfo.fromJson(_fiscalJson) : null,
      );
    }

    void expectPdf(Uint8List bytes) {
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1500));
    }

    testWidgets('builds a roll-sized document for saving', (tester) async {
      final bytes = await tester.runAsync(() => buildReceiptPdf(data()));
      expectPdf(bytes!);
    });

    testWidgets('builds a centred receipt on a sheet for printing', (tester) async {
      final bytes = await tester.runAsync(
        () => buildReceiptPdf(data(), format: PdfPageFormat.a4),
      );
      expectPdf(bytes!);
    });

    testWidgets('builds without fiscal details or items', (tester) async {
      final bytes = await tester.runAsync(
        () => buildReceiptPdf(data(fiscal: false, empty: true)),
      );
      expectPdf(bytes!);
    });
  });

  group('receipt data', () {
    test('falls back to the sale number and a default business name', () {
      final d = ReceiptData(sale: Sale.fromJson(_saleJson()));
      expect(d.businessName, 'Kantemba POS');
      expect(d.receiptNumber, 'S-0007');
      expect(d.fileName, 'receipt-S-0007.pdf');
      expect(d.footer, 'Thank you for your purchase.');
    });

    test('file names never contain unsafe characters', () {
      final json = _saleJson()..['saleNumber'] = 'S/2026 07:1';
      expect(ReceiptData(sale: Sale.fromJson(json)).fileName, 'receipt-S_2026_07_1.pdf');
    });
  });

  group('checkout sale flow', () {
    Future<FakeServer> pumpCheckout(WidgetTester tester) async {
      final server = FakeServer()
        ..products['6001'] = productJson(1, '6001', name: 'Milk', price: 10, stock: 5)
        ..customers = [
          {'id': 5, 'firstName': 'Mary', 'lastName': 'Banda', 'phone': '0977123456', 'isActive': true},
          {'id': 6, 'firstName': 'John', 'lastName': 'Phiri', 'phone': '0966000111', 'isActive': true},
        ];
      final session = await server.signedInSession();
      await tester.pumpWidget(SessionScope(
        session: session,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CheckoutScreen(active: false),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets('a customer can be attached and is sent with the sale', (tester) async {
      final server = await pumpCheckout(tester);
      expect(find.text('Walk-in customer'), findsOneWidget);

      await tester.tap(find.text('Walk-in customer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Search name or phone').last, 'phiri');
      await tester.pumpAndSettle();
      expect(find.text('Mary Banda'), findsNothing);
      await tester.tap(find.text('John Phiri'));
      await tester.pumpAndSettle();
      expect(find.text('John Phiri'), findsOneWidget);

      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(server.bodyOf(server.posts('/sales').single)['customerId'], 6);
      expect(find.text('Sale complete'), findsOneWidget);
      // The customer does not carry over to the next sale.
      await tester.tap(find.text('New sale'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.text('Walk-in customer'), findsOneWidget);
    });

    testWidgets('the cash prompt offers quick amounts and shows the change due', (tester) async {
      await pumpCheckout(tester);
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('Exact'), findsOneWidget);
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      expect(find.text('Change due: 8.40'), findsOneWidget); // total is 11.60

      await tester.enterText(find.widgetWithText(TextField, 'Amount received (leave empty for exact)'), '5');
      await tester.pump();
      expect(find.textContaining('Short by 6.60'), findsOneWidget);

      await tester.tap(find.text('Exact'));
      await tester.pump();
      expect(find.textContaining('Estimated total 11.60'), findsOneWidget);
    });
  });
}
