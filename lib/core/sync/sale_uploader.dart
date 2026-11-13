import '../../data/local/sale_queue.dart';
import '../../data/local/sync_meta.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/sync_api.dart';
import '../api/api_exception.dart';
import 'device_identity.dart';

/// What one [SaleUploader.run] did.
class UploadResult {
  const UploadResult({
    this.uploaded = 0,
    this.duplicates = 0,
    this.rejected = 0,
    this.pending = 0,
    this.conflicts = 0,
    this.error,
    this.unreachable = false,
  });

  /// Sales the server recorded now.
  final int uploaded;

  /// Sales the server already had (an earlier upload whose reply was lost).
  final int duplicates;

  /// Sales the server refused; they stay on the device for a decision.
  final int rejected;

  /// Sales still waiting to upload after the run.
  final int pending;

  /// Recorded sales the server flagged for a manager to review.
  final int conflicts;

  /// Why the run stopped early, if it did.
  final String? error;

  /// True when the stop was a connection failure rather than a refusal.
  final bool unreachable;

  bool get ok => error == null;
}

/// Sends the sales made offline to the server.
///
/// Sales go oldest first in batches of [batchSize]. Each answer is applied
/// sale by sale: `CREATED` and `DUPLICATE` mean the server has it, so it
/// leaves the queue; `REJECTED` keeps it with the server's reason and it is
/// not sent again until someone requeues it. A sale the answer does not
/// mention stays queued. Any failure — no connection, or the whole request
/// refused (for example the till was deactivated) — stops the run with the
/// queue untouched, and the next run sends the same sales again. That is safe
/// because the server answers a sale it already recorded with `DUPLICATE`.
///
/// Whenever the server was reached the run ends with a heartbeat, so a till
/// with an empty queue still shows as online.
class SaleUploader {
  SaleUploader({
    required this._api,
    required this._queue,
    required this._meta,
    required this._identity,
    this.appVersion,
    this.batchSize = 50,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncApi _api;
  final SaleQueue _queue;
  final SyncMeta _meta;
  final DeviceIdentity _identity;
  final String? appVersion;

  /// Kept under the server's own limit (`SYNC_MAX_BATCH_SIZE`, 100 by
  /// default), which refuses a larger batch outright.
  final int batchSize;
  final DateTime Function() _clock;

  Future<UploadResult>? _running;

  /// Uploads everything pending. A call made while a run is under way joins
  /// it instead of starting a second one.
  ///
  /// Never throws: this runs unattended in the background, so an unexpected
  /// failure (say, the local database) comes back as [UploadResult.error]
  /// for the status screen instead of an unhandled error.
  Future<UploadResult> run() => _running ??= _guarded().whenComplete(
    () => _running = null,
  );

  Future<UploadResult> _guarded() async {
    try {
      return await _upload();
    } catch (e) {
      return UploadResult(error: 'Upload failed: $e');
    }
  }

  Future<UploadResult> _upload() async {
    final deviceId = await _identity.deviceId();
    var uploaded = 0;
    var duplicates = 0;
    var rejected = 0;
    var conflicts = 0;
    String? error;
    var unreachable = false;

    while (true) {
      final batch = await _queue.pending(limit: batchSize);
      if (batch.isEmpty) break;

      final stillQueued =
          await _queue.pendingCount() + await _queue.rejectedCount();
      await _queue.recordAttempt([for (final s in batch) s.clientSaleId]);

      final SyncSalesResponse response;
      try {
        response = await _api.uploadSales(
          deviceId: deviceId,
          pendingQueueSize: stillQueued - batch.length,
          sales: [for (final sale in batch) sale.draft],
        );
      } on ApiException catch (e) {
        error = e.message;
        unreachable = e.isNetwork;
        break;
      } on FormatException catch (e) {
        error = 'Unexpected answer from the server: ${e.message}';
        break;
      }

      final byId = {for (final r in response.results) r.clientSaleId: r};
      var applied = 0;
      for (final sale in batch) {
        final result = byId[sale.clientSaleId];
        if (result == null) continue;
        if (result.isRecorded) {
          await _queue.markUploaded(sale.clientSaleId);
          if (result.status == 'CREATED') {
            uploaded++;
            if (result.conflicts.isNotEmpty) conflicts++;
          } else {
            duplicates++;
          }
          applied++;
        } else if (result.isRejected) {
          await _queue.markRejected(
            sale.clientSaleId,
            result.error ?? 'Rejected by the server.',
          );
          rejected++;
          applied++;
        }
      }
      if (uploaded + duplicates > 0) {
        await _meta.set(
          SyncMeta.lastUploadKey,
          formatLocalDateTime(_clock()),
        );
      }
      // An answer that settled nothing would be asked again forever.
      if (applied == 0) {
        error = 'The server did not settle any of the ${batch.length} sales.';
        break;
      }
    }

    final pending = await _queue.pendingCount();
    if (!unreachable) await _heartbeat(deviceId, pending);

    return UploadResult(
      uploaded: uploaded,
      duplicates: duplicates,
      rejected: rejected,
      conflicts: conflicts,
      pending: pending,
      error: error,
      unreachable: unreachable,
    );
  }

  /// Best effort: a missed heartbeat only means the dashboard is a little
  /// stale. Rejected sales still count as waiting on this till.
  Future<void> _heartbeat(String deviceId, int pending) async {
    try {
      await _api.heartbeat(
        deviceId: deviceId,
        pendingQueueSize: pending + await _queue.rejectedCount(),
        online: true,
        appVersion: appVersion,
      );
    } catch (_) {}
  }
}
