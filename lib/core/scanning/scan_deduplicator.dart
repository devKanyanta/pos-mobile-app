/// Suppresses repeated camera detections of the same barcode.
///
/// A barcode is accepted once; while the camera keeps seeing it, further
/// detections are ignored. It is accepted again only after it has not been
/// seen for [cooldown], or after a different barcode was accepted in between.
/// An intentional re-scan (the code is lifted and presented again) therefore
/// adds another unit.
class ScanDeduplicator {
  ScanDeduplicator({this.cooldown = const Duration(milliseconds: 1500)});

  final Duration cooldown;
  String? _lastCode;
  DateTime? _lastSeen;

  /// Returns true if [code] should be processed at time [now].
  bool accept(String code, DateTime now) {
    final last = _lastSeen;
    final sameCode = code == _lastCode;
    final stillVisible = last != null && now.difference(last) < cooldown;
    if (sameCode && stillVisible) {
      _lastSeen = now;
      return false;
    }
    _lastCode = code;
    _lastSeen = now;
    return true;
  }

  void reset() {
    _lastCode = null;
    _lastSeen = null;
  }
}
