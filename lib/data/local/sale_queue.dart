import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/sync_models.dart';

/// The outbox of sales made while offline.
///
/// A sale enters as PENDING, is uploaded by the sync worker, and leaves the
/// queue when the server answers `CREATED` or `DUPLICATE` ([markUploaded]).
/// A `REJECTED` answer keeps the row with the server's error ([markRejected])
/// until someone retries it ([requeue]) or discards it ([remove]). The row
/// stores the exact upload payload, so what was queued is what is sent.
class SaleQueue {
  SaleQueue(this._db);

  final Database _db;

  /// Queues [draft]. Queueing the same `clientSaleId` again does nothing, so
  /// a retried checkout cannot create two rows.
  Future<void> enqueue(OfflineSaleDraft draft, {DateTime? now}) async {
    await _db.insert('queued_sales', {
      'client_sale_id': draft.clientSaleId,
      'payload': jsonEncode(draft.toJson()),
      'status': QueuedSaleStatus.pending.wireName,
      'sold_at': formatLocalDateTime(draft.soldAt),
      'expected_total': draft.expectedTotal,
      'created_at': formatLocalDateTime(now ?? DateTime.now()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Oldest-first PENDING sales, up to [limit] (the upload batch size).
  Future<List<QueuedSale>> pending({int limit = 100}) async {
    final rows = await _db.query(
      'queued_sales',
      where: 'status = ?',
      whereArgs: [QueuedSaleStatus.pending.wireName],
      orderBy: 'created_at, client_sale_id',
      limit: limit,
    );
    return rows.map(_toQueuedSale).toList(growable: false);
  }

  /// Every queued sale, oldest first, for the sync status screen.
  Future<List<QueuedSale>> all() async {
    final rows = await _db.query(
      'queued_sales',
      orderBy: 'created_at, client_sale_id',
    );
    return rows.map(_toQueuedSale).toList(growable: false);
  }

  /// The queued sale with this id, whatever its status, or null.
  Future<QueuedSale?> find(String clientSaleId) async {
    final rows = await _db.query(
      'queued_sales',
      where: 'client_sale_id = ?',
      whereArgs: [clientSaleId],
    );
    return rows.isEmpty ? null : _toQueuedSale(rows.first);
  }

  /// Units of each product sold in PENDING sales that the server has not
  /// seen yet, keyed by product id. The server will deduct them when the
  /// sales upload, so until then they are no longer on the shelf.
  Future<Map<int, int>> pendingQuantities() async {
    final rows = await _db.query(
      'queued_sales',
      columns: ['payload'],
      where: 'status = ?',
      whereArgs: [QueuedSaleStatus.pending.wireName],
    );
    final totals = <int, int>{};
    for (final row in rows) {
      final draft = OfflineSaleDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String)),
      );
      for (final item in draft.items) {
        totals.update(
          item.productId,
          (n) => n + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
    }
    return totals;
  }

  Future<int> pendingCount() => _count(QueuedSaleStatus.pending);

  Future<int> rejectedCount() => _count(QueuedSaleStatus.rejected);

  /// Counts an upload attempt on each of [clientSaleIds] (call before the
  /// batch request, so a crash mid-upload still shows in the history).
  Future<void> recordAttempt(
    Iterable<String> clientSaleIds, {
    DateTime? now,
  }) async {
    final at = formatLocalDateTime(now ?? DateTime.now());
    final batch = _db.batch();
    for (final id in clientSaleIds) {
      batch.rawUpdate(
        'UPDATE queued_sales SET attempts = attempts + 1, '
        'last_attempt_at = ? WHERE client_sale_id = ?',
        [at, id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// The server recorded the sale (`CREATED` or `DUPLICATE`): drop it.
  Future<void> markUploaded(String clientSaleId) async {
    await _db.delete(
      'queued_sales',
      where: 'client_sale_id = ?',
      whereArgs: [clientSaleId],
    );
  }

  /// The server refused the sale; keep it with [error] for review.
  Future<void> markRejected(String clientSaleId, String error) async {
    await _db.update(
      'queued_sales',
      {'status': QueuedSaleStatus.rejected.wireName, 'error': error},
      where: 'client_sale_id = ?',
      whereArgs: [clientSaleId],
    );
  }

  /// Puts a rejected sale back in line for the next upload.
  Future<void> requeue(String clientSaleId) async {
    await _db.update(
      'queued_sales',
      {'status': QueuedSaleStatus.pending.wireName, 'error': null},
      where: 'client_sale_id = ?',
      whereArgs: [clientSaleId],
    );
  }

  /// Discards a sale (a manager gave up on a rejected one).
  Future<void> remove(String clientSaleId) => markUploaded(clientSaleId);

  Future<int> _count(QueuedSaleStatus status) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM queued_sales WHERE status = ?',
      [status.wireName],
    );
    return rows.first['n'] as int;
  }

  static QueuedSale _toQueuedSale(Map<String, Object?> row) {
    final payload = jsonDecode(row['payload'] as String);
    return QueuedSale(
      draft: OfflineSaleDraft.fromJson(Map<String, dynamic>.from(payload)),
      status: QueuedSaleStatus.parse(row['status'] as String?),
      attempts: (row['attempts'] as int?) ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      error: row['error'] as String?,
      lastAttemptAt: switch (row['last_attempt_at']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
    );
  }
}
