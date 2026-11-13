import 'package:sqflite/sqflite.dart';

/// Key–value sync state that must survive restarts: the device identity and
/// the sync bookmarks.
class SyncMeta {
  SyncMeta(this._db);

  final Database _db;

  /// The stable id this till registered with (`POST /sync/devices/register`).
  static const deviceIdKey = 'deviceId';

  /// The API base URL the till last registered against; a different URL
  /// means a different server, so registration runs again.
  static const deviceRegisteredUrlKey = 'deviceRegisteredUrl';

  /// `serverTime` of the last catalogue pull — sent back as `since`.
  static const catalogSinceKey = 'catalogSince';

  /// Device-local time of the last successful catalogue pull.
  static const lastCatalogSyncKey = 'lastCatalogSyncAt';

  /// Device-local time of the last successful sales upload.
  static const lastUploadKey = 'lastUploadAt';

  /// Last offline receipt number handed out on this till (a counter).
  static const offlineReceiptSeqKey = 'offlineReceiptSeq';

  /// The business profile as last fetched, for receipts printed offline.
  static const merchantKey = 'merchantProfile';

  Future<String?> get(String key) async {
    final rows = await _db.query(
      'sync_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await _db.insert('sync_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String key) async {
    await _db.delete('sync_meta', where: 'key = ?', whereArgs: [key]);
  }
}
