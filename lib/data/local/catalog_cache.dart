import 'package:sqflite/sqflite.dart';

import '../models/catalog_models.dart';
import '../models/sync_models.dart';

/// The device's copy of the catalogue, fed by `GET /sync/catalog` deltas and
/// read by checkout when the server is unreachable.
///
/// Lookups return only active products (the same as the server's barcode
/// endpoint) and expect canonical barcodes — normalise scans first.
class CatalogCache {
  CatalogCache(this._db);

  final Database _db;

  static const _productSelect = '''
    SELECT p.*, c.name AS category_name
    FROM products p LEFT JOIN categories c ON c.id = p.category_id
  ''';

  /// Inserts or updates [products] (a full snapshot or a delta).
  Future<void> applyProducts(List<CatalogProduct> products) async {
    if (products.isEmpty) return;
    final batch = _db.batch();
    for (final product in products) {
      batch.insert('products', {
        'id': product.id,
        'name': product.name,
        'sku': product.sku,
        'barcode': product.barcode,
        'price': product.price,
        'vat_rate': product.vatRate,
        'zra_tax_type': product.zraTaxType,
        'track_inventory': product.trackInventory ? 1 : 0,
        'stock_quantity': product.stockQuantity,
        'active': product.active ? 1 : 0,
        'category_id': product.categoryId,
        'updated_at': product.updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Deletes cached products the server no longer has. [serverIds] is the
  /// complete id list from the catalogue response.
  Future<void> removeProductsNotIn(Iterable<int> serverIds) async {
    final keep = serverIds.toSet();
    final rows = await _db.query('products', columns: ['id']);
    final stale = [
      for (final row in rows)
        if (!keep.contains(row['id'] as int)) row['id'] as int,
    ];
    if (stale.isEmpty) return;
    final batch = _db.batch();
    for (final id in stale) {
      batch.delete('products', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Replaces the category list (the response always carries all of them).
  Future<void> replaceCategories(List<Category> categories) =>
      _db.transaction((txn) async {
        await txn.delete('categories');
        for (final category in categories) {
          await txn.insert('categories', {
            'id': category.id,
            'name': category.name,
          });
        }
      });

  /// Replaces the payment method list.
  Future<void> replacePaymentMethods(List<PaymentMethod> methods) =>
      _db.transaction((txn) async {
        await txn.delete('payment_methods');
        for (final method in methods) {
          await txn.insert('payment_methods', {
            'id': method.id,
            'name': method.name,
            'code': method.code,
            'type': method.type,
            'requires_reference': method.requiresReference ? 1 : 0,
            'is_active': method.isActive ? 1 : 0,
          });
        }
      });

  /// Active product with this canonical [barcode], or null.
  Future<Product?> productByBarcode(String barcode) async {
    final rows = await _db.rawQuery(
      '$_productSelect WHERE p.barcode = ? AND p.active = 1 LIMIT 1',
      [barcode],
    );
    return rows.isEmpty ? null : _toProduct(rows.first);
  }

  Future<Product?> productById(int id) async {
    final rows = await _db.rawQuery('$_productSelect WHERE p.id = ?', [id]);
    return rows.isEmpty ? null : _toProduct(rows.first);
  }

  /// Active products whose name contains [query], or whose SKU or barcode
  /// equals it, by name.
  Future<List<Product>> searchProducts(String query, {int limit = 50}) async {
    final needle = query.trim();
    final rows = await _db.rawQuery(
      '$_productSelect WHERE p.active = 1 AND '
      "(p.name LIKE ? COLLATE NOCASE OR p.sku = ? OR p.barcode = ?) "
      'ORDER BY p.name LIMIT ?',
      ['%$needle%', needle, needle.toUpperCase(), limit],
    );
    return rows.map(_toProduct).toList(growable: false);
  }

  Future<List<Category>> categories() async {
    final rows = await _db.query('categories', orderBy: 'name');
    return [
      for (final row in rows)
        Category(id: row['id'] as int, name: row['name'] as String),
    ];
  }

  Future<List<PaymentMethod>> paymentMethods() async {
    final rows = await _db.query('payment_methods', orderBy: 'id');
    return [
      for (final row in rows)
        PaymentMethod(
          id: row['id'] as int,
          name: row['name'] as String,
          code: row['code'] as String,
          type: row['type'] as String,
          requiresReference: row['requires_reference'] == 1,
          isActive: row['is_active'] == 1,
        ),
    ];
  }

  /// How many products are cached — zero means no catalogue has ever been
  /// pulled, so offline checkout cannot work yet.
  Future<int> productCount() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM products');
    return rows.first['n'] as int;
  }

  static Product _toProduct(Map<String, Object?> row) => CatalogProduct(
    id: row['id'] as int,
    name: row['name'] as String,
    sku: row['sku'] as String?,
    barcode: row['barcode'] as String?,
    price: (row['price'] as num).toDouble(),
    vatRate: (row['vat_rate'] as num).toDouble(),
    zraTaxType: row['zra_tax_type'] as String?,
    trackInventory: row['track_inventory'] == 1,
    stockQuantity: row['stock_quantity'] as int,
    active: row['active'] == 1,
    categoryId: row['category_id'] as int?,
    updatedAt: row['updated_at'] as String?,
  ).toProduct(categoryName: row['category_name'] as String?);
}
