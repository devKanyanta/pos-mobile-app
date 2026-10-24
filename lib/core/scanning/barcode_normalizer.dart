/// Client-side mirror of the backend's barcode rules (`Barcodes.java`), used to
/// give instant feedback. The server stays the authority and re-validates.
///
/// Stored barcodes are upper-case, 3-64 characters of letters, digits and
/// `. _ / + -` with no spaces.
class BarcodeNormalizer {
  const BarcodeNormalizer._();

  static const int minLength = 3;
  static const int maxLength = 64;

  static final RegExp _valid = RegExp(r'^[A-Z0-9._/+\-]{3,64}$');
  static final RegExp _scientific = RegExp(r'^\d+(\.\d+)?E[+-]?\d+$');

  /// Trimmed and upper-cased, or null when blank. Used for lookups.
  static String? canonical(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.toUpperCase();
  }

  /// Whether [canonicalCode] can be stored as a barcode.
  static bool isValid(String? canonicalCode) =>
      canonicalCode != null &&
      _valid.hasMatch(canonicalCode) &&
      !_scientific.hasMatch(canonicalCode);

  /// A human-readable problem with [raw], or null when it is acceptable (or blank).
  static String? validate(String? raw) {
    final code = canonical(raw);
    if (code == null) return null;
    if (_scientific.hasMatch(code)) {
      return 'This looks like a number in scientific notation. Re-scan or type the full barcode.';
    }
    if (!_valid.hasMatch(code)) {
      return 'Use $minLength-$maxLength letters, digits or . _ / + - (no spaces).';
    }
    return null;
  }
}
