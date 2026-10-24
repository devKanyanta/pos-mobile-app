import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

/// Retail symbologies the app reads: EAN-13, EAN-8, UPC-A, UPC-E and Code 128.
const List<BarcodeFormat> kRetailBarcodeFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
];

/// Live camera preview that reports detected barcode values.
///
/// This widget only owns the camera. It does no de-duplication, lookups or
/// business rules: it forwards every raw value to [onBarcode] and leaves the
/// decisions to the caller (see `ScanCheckoutController`).
///
/// * While [enabled] is false no camera is open, so a screen that is hidden
///   (another tab, a covering page) never holds the camera.
/// * The scanner package stops and restarts the camera with the app lifecycle.
/// * If the camera cannot be used (permission denied, no camera) a message
///   with a retry button replaces the preview; the caller keeps manual entry.
class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({
    super.key,
    required this.onBarcode,
    this.enabled = true,
    this.height = 200,
    this.hint = 'Point the camera at a barcode',
  });

  final void Function(String rawValue) onBarcode;
  final bool enabled;
  final double height;
  final String hint;

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  MobileScannerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller = _createController();
  }

  @override
  void didUpdateWidget(BarcodeScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _controller = _createController();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  MobileScannerController _createController() => MobileScannerController(
    // Every frame set is reported (at most every 250 ms); the caller
    // filters repeats so that a deliberate re-scan still counts.
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
    formats: kRetailBarcodeFormats,
  );

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        widget.onBarcode(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.surface),
        child: controller == null
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_off_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        'Scanner paused',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) =>
                        _CameraProblem(error: error, onRetry: controller.start),
                  ),
                  const IgnorePointer(child: _ViewfinderFrame()),
                  Positioned(
                    bottom: Gap.md,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.md,
                            vertical: 6,
                          ),
                          child: Text(
                            widget.hint,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: Gap.sm,
                    top: Gap.sm,
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: controller,
                      builder: (context, state, _) {
                        final on = state.torchState == TorchState.on;
                        return IconButton.filledTonal(
                          tooltip: on
                              ? 'Turn flashlight off'
                              : 'Turn flashlight on',
                          style: IconButton.styleFrom(
                            backgroundColor: on
                                ? scheme.primaryContainer
                                : Colors.black.withValues(alpha: 0.45),
                            foregroundColor: on
                                ? scheme.onPrimaryContainer
                                : Colors.white,
                          ),
                          icon: Icon(
                            on
                                ? Icons.flashlight_on
                                : Icons.flashlight_off_outlined,
                          ),
                          onPressed: controller.toggleTorch,
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Four corner brackets that tell the user where to aim; purely decorative.
class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 240,
    height: 110,
    child: CustomPaint(painter: _BracketPainter()),
  );
}

class _BracketPainter extends CustomPainter {
  const _BracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 22.0;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, 0)
      ..lineTo(arm, 0)
      ..moveTo(w - arm, 0)
      ..lineTo(w, 0)
      ..lineTo(w, arm)
      ..moveTo(w, h - arm)
      ..lineTo(w, h)
      ..lineTo(w - arm, h)
      ..moveTo(arm, h)
      ..lineTo(0, h)
      ..lineTo(0, h - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BracketPainter oldDelegate) => false;
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error, required this.onRetry});

  final MobileScannerException error;
  final Future<void> Function({CameraFacing? cameraDirection}) onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final message = denied
        ? 'Camera permission denied. Allow camera access in the phone settings, or type the barcode below.'
        : unsupported
        ? 'This device cannot scan barcodes. Type the barcode below.'
        : 'The camera is unavailable. Type the barcode below.';
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 28,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Gap.sm),
              Text(message, textAlign: TextAlign.center),
              if (!unsupported)
                TextButton(
                  onPressed: () => onRetry(),
                  child: const Text('Try again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
