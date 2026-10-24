import '../../data/models/catalog_models.dart';
import '../api/api_exception.dart';
import '../checkout/product_lookup.dart';
import '../scanning/barcode_normalizer.dart';

enum BarcodeStatus {
  /// Field left blank: the product simply has no barcode.
  none,

  /// Well-formed and not used by another product.
  available,

  /// Not a storable barcode; see [BarcodeCheck.message].
  invalid,

  /// Another product already carries it; see [BarcodeCheck.owner].
  taken,

  /// The server could not be asked (offline, permission); saving will re-check.
  unverified,
}

class BarcodeCheck {
  const BarcodeCheck(this.status, {this.code, this.message, this.owner});

  final BarcodeStatus status;

  /// The canonical barcode that was checked.
  final String? code;
  final String? message;
  final Product? owner;

  bool get blocksSaving =>
      status == BarcodeStatus.invalid || status == BarcodeStatus.taken;
}

/// Decides whether a barcode may be assigned to a product, before saving.
///
/// Scanning a code must never silently create a second product for it: if the
/// code exists, the caller gets the owner so it can offer to open that product
/// or add stock instead.
class BarcodeAssignmentChecker {
  const BarcodeAssignmentChecker(this._lookup);

  final ProductLookup _lookup;

  /// [editingProductId] is the product being edited (its own barcode is fine).
  Future<BarcodeCheck> check(String? raw, {int? editingProductId}) async {
    final code = BarcodeNormalizer.canonical(raw);
    if (code == null) return const BarcodeCheck(BarcodeStatus.none);

    final problem = BarcodeNormalizer.validate(code);
    if (problem != null) {
      return BarcodeCheck(BarcodeStatus.invalid, code: code, message: problem);
    }

    try {
      final owner = await _lookup.findByBarcode(code);
      if (owner != null && owner.id != editingProductId) {
        return BarcodeCheck(
          BarcodeStatus.taken,
          code: code,
          owner: owner,
          message: 'Barcode $code is already assigned to ${owner.name}.',
        );
      }
      return BarcodeCheck(BarcodeStatus.available, code: code);
    } on ApiException catch (e) {
      return BarcodeCheck(
        BarcodeStatus.unverified,
        code: code,
        message: e.isNetwork
            ? 'Could not check this barcode (no connection). It will be checked when you save.'
            : e.message,
      );
    }
  }
}
