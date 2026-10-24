import 'package:flutter/material.dart';

import '../core/scanning/barcode_normalizer.dart';
import 'theme/app_theme.dart';
import 'widgets/barcode_scanner_view.dart';

/// Full-screen scanner that returns one barcode to the caller.
///
/// `Navigator.pop` receives the canonical barcode (or null if cancelled). A
/// text field offers manual entry when the camera is unavailable.
class ScanBarcodeScreen extends StatefulWidget {
  const ScanBarcodeScreen({super.key, this.title = 'Scan barcode'});

  final String title;

  @override
  State<ScanBarcodeScreen> createState() => _ScanBarcodeScreenState();
}

class _ScanBarcodeScreenState extends State<ScanBarcodeScreen> {
  final TextEditingController _manual = TextEditingController();
  bool _done = false;
  String? _problem;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _accept(String raw) {
    if (_done) return;
    final code = BarcodeNormalizer.canonical(raw);
    final problem = BarcodeNormalizer.validate(code);
    if (code == null || problem != null) {
      setState(() => _problem = problem ?? 'Enter a barcode.');
      return;
    }
    _done = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BarcodeScannerView(
              height: 300,
              enabled: !_done,
              onBarcode: _accept,
            ),
            const SizedBox(height: Gap.xl),
            TextField(
              controller: _manual,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Or type the barcode',
                errorText: _problem,
                prefixIcon: const Icon(Icons.keyboard_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Use this barcode',
                  icon: const Icon(Icons.check),
                  onPressed: () => _accept(_manual.text),
                ),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_problem != null) setState(() => _problem = null);
              },
              onSubmitted: _accept,
            ),
          ],
        ),
      ),
    );
  }
}
