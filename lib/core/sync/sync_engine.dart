import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/database/milk_collection_local_repository.dart';
import 'package:wakulima/core/network/api_client.dart';

enum SyncStatus { idle, syncing, success, failed }

class SyncProgress {
  final int total;
  final int done;
  final String? currentItem;

  const SyncProgress({required this.total, required this.done, this.currentItem});

  double get fraction => total == 0 ? 0 : done / total;
  bool   get isComplete => done >= total;

  /// Percentage string e.g. "42%"
  String get percent => '${(fraction * 100).round()}%';
}

/// Offline-first sync engine.
/// Reads unsynced MilkCollectionModel records from Isar, groups them by
/// (shiftId + date) so each calendar day becomes a separate purchase batch,
/// POSTs each batch to /farmers/milk-purchases, then marks them synced.
class SyncEngine {
  static final SyncEngine _instance = SyncEngine._();
  factory SyncEngine() => _instance;
  SyncEngine._();

  final _statusController   = StreamController<SyncStatus>.broadcast();
  final _progressController = StreamController<SyncProgress>.broadcast();
  final _pendingCountController = StreamController<int>.broadcast();

  Stream<SyncStatus>  get statusStream       => _statusController.stream;
  Stream<SyncProgress> get progressStream    => _progressController.stream;
  Stream<int>          get pendingCountStream => _pendingCountController.stream;

  SyncStatus   _status       = SyncStatus.idle;
  SyncStatus   get status    => _status;
  SyncProgress? _lastProgress;
  SyncProgress? get lastProgress => _lastProgress;

  int  _pendingCount = 0;
  int  get pendingCount => _pendingCount;

  Timer? _syncTimer;
  bool   _isOnline = false;
  bool   get isOnline => _isOnline;

  final _repo = MilkCollectionLocalRepository();

  Future<void> init() async {
    await refreshPendingCount();

    final result = await Connectivity().checkConnectivity();
    _isOnline = result.any((r) => r != ConnectivityResult.none);

    Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline = result.any((r) => r != ConnectivityResult.none);
      if (wasOffline && _isOnline) syncNow();
    });

    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isOnline) syncNow();
    });
  }

  Future<void> refreshPendingCount() async {
    _pendingCount = await _repo.pendingCount();
    _pendingCountController.add(_pendingCount);
  }

  Future<void> syncNow() async {
    if (_status == SyncStatus.syncing) return;
    _setStatus(SyncStatus.syncing);
    try {
      await _flushQueue();
      await refreshPendingCount();
      _setStatus(SyncStatus.success);
    } catch (e) {
      _setStatus(SyncStatus.failed);
    }
  }

  Future<void> _flushQueue() async {
    final pending = await _repo.getPending();
    if (pending.isEmpty) return;

    final box  = Hive.box('auth');
    final route = box.get('route') as Map?;
    final user  = box.get('user')  as Map?;

    final routeId          = (route?['id']          as num?)?.toInt();
    final graderLocationId = (user?['location_id']  as num?)?.toInt();

    if (routeId == null) return; // can't sync without route

    // Group records by (shiftId + calendar date) so each day is a separate batch.
    // Key format: "<shiftId>|<yyyy-MM-dd>"
    final byShiftDate = <String, List>{};
    for (final record in pending) {
      final shift = record.shiftId ?? 0;
      final date  = _isoDate(record.collectedAt);
      final key   = '${shift}|$date';
      byShiftDate.putIfAbsent(key, () => []).add(record);
    }

    int done  = 0;
    final total = pending.length;

    // Emit initial 0-progress so the UI shows the bar immediately
    _emitProgress(total, 0, 'Preparing ${total} record(s)…');

    for (final entry in byShiftDate.entries) {
      final parts   = entry.key.split('|');
      final shiftId = int.tryParse(parts[0]) ?? 0;
      final date    = parts[1];
      final records = entry.value;

      if (shiftId == 0) {
        // No shift assigned — skip (no POST without a valid shift)
        done += records.length;
        _emitProgress(total, done, 'Skipped ${records.length} record(s) with no shift');
        continue;
      }

      _emitProgress(total, done,
          'Syncing ${records.length} record(s) — shift $shiftId, $date…');

      try {
        final api   = ApiClient();
        final items = records.map((r) => {
          'farmer_id': r.farmerServerId ?? 0,
          'quantity':  r.weightKg,
        }).toList();

        final response = await api.post('/farmers/milk-purchases', data: {
          'route_id':     routeId,
          'shift_id':     shiftId,
          'grader_id':    graderLocationId,
          'invoice_date': date,
          'items':        items,
        });

        final body = response.data as Map<String, dynamic>;
        if (body['success'] == true) {
          for (final r in records) {
            await _repo.markSynced(r.id);
          }
        }
      } catch (_) {
        // Leave unsynced — will retry next cycle
      }

      done += records.length;
      _emitProgress(total, done);
    }

    // Final 100 % signal
    _emitProgress(total, total);
  }

  void _emitProgress(int total, int done, [String? msg]) {
    final p = SyncProgress(total: total, done: done, currentItem: msg);
    _lastProgress = p;
    _progressController.add(p);
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    _statusController.add(s);
  }

  static String _isoDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void dispose() {
    _syncTimer?.cancel();
    _statusController.close();
    _progressController.close();
    _pendingCountController.close();
  }
}
