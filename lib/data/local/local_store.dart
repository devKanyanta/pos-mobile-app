import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'catalog_cache.dart';
import 'sale_queue.dart';
import 'sync_meta.dart';

export 'catalog_cache.dart';
export 'sale_queue.dart';
export 'sync_meta.dart';

/// The device's SQLite database: the cached catalogue, the outbox of sales
/// made offline, and sync metadata (device id, last sync times).
///
/// One instance lives for the whole app. Open it with [LocalStore.open]; the
/// default factory and path are the device database, while tests pass the FFI
/// factory and an in-memory path. All access goes through [catalog],
/// [saleQueue] and [meta] — no other code touches the database.
class LocalStore {
  LocalStore._(this._db)
    : catalog = CatalogCache(_db),
      saleQueue = SaleQueue(_db),
      meta = SyncMeta(_db);

  final Database _db;

  final CatalogCache catalog;
  final SaleQueue saleQueue;
  final SyncMeta meta;

  static const _version = 1;

  static Future<LocalStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'kantemba.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: _version, onCreate: _create),
    );
    return LocalStore._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        price REAL NOT NULL,
        vat_rate REAL NOT NULL DEFAULT 0,
        zra_tax_type TEXT,
        track_inventory INTEGER NOT NULL DEFAULT 1,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        category_id INTEGER,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE payment_methods(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        type TEXT NOT NULL,
        requires_reference INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE queued_sales(
        client_sale_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        error TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        sold_at TEXT NOT NULL,
        expected_total REAL,
        created_at TEXT NOT NULL,
        last_attempt_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_queued_sales_status ON queued_sales(status, created_at)',
    );
    await db.execute('''
      CREATE TABLE sync_meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() => _db.close();
}
