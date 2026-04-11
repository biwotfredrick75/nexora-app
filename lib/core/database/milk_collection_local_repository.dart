import 'package:isar/isar.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/milk_collection_model.dart';

class MilkCollectionLocalRepository {
  /// Target number of demo records to seed.
  static const int demoTargetCount = 5000;

  // ── Core CRUD ────────────────────────────────────────────────────────────

  /// Save a new collection record locally (offline-first).
  Future<MilkCollectionModel> save(MilkCollectionModel model) async {
    final isar = await AppDatabase.instance;
    await isar.writeTxn(() async {
      model.id = await isar.milkCollectionModels.put(model);
    });
    return model;
  }

  /// All unsynced records — used by SyncEngine.
  Future<List<MilkCollectionModel>> getPending() async {
    final isar = await AppDatabase.instance;
    return isar.milkCollectionModels
        .where()
        .syncedEqualTo(false)
        .findAll();
  }

  /// Mark a record as synced.
  Future<void> markSynced(int isarId) async {
    final isar = await AppDatabase.instance;
    await isar.writeTxn(() async {
      final record = await isar.milkCollectionModels.get(isarId);
      if (record != null) {
        record.synced = true;
        record.syncedAt = DateTime.now();
        await isar.milkCollectionModels.put(record);
      }
    });
  }

  /// Count of unsynced records.
  Future<int> pendingCount() async {
    final isar = await AppDatabase.instance;
    return isar.milkCollectionModels.where().syncedEqualTo(false).count();
  }

  /// All records (synced + unsynced) for display.
  Future<List<MilkCollectionModel>> getAll({int limit = 200}) async {
    final isar = await AppDatabase.instance;
    return isar.milkCollectionModels
        .where()
        .sortByCollectedAtDesc()
        .limit(limit)
        .findAll();
  }

  // ── Duplicate detection ──────────────────────────────────────────────────

  /// Returns true if an unsynced record already exists for the same
  /// farmer + shift + calendar day (prevents double-entry for a session).
  Future<bool> hasDuplicate({
    required int farmerServerId,
    required int shiftId,
    required DateTime date,
  }) async {
    final pending  = await getPending();
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd   = dayStart.add(const Duration(days: 1));
    return pending.any((r) =>
        r.farmerServerId == farmerServerId &&
        r.shiftId        == shiftId &&
        !r.collectedAt.isBefore(dayStart) &&
        r.collectedAt.isBefore(dayEnd));
  }

  // ── Safe clear ───────────────────────────────────────────────────────────

  /// Delete synced records. Returns false (blocked) if unsynced records remain.
  Future<bool> clearSynced() async {
    if (await pendingCount() > 0) return false;
    final isar = await AppDatabase.instance;
    await isar.writeTxn(
      () => isar.milkCollectionModels.where().syncedEqualTo(true).deleteAll(),
    );
    return true;
  }

  /// Delete ALL local records. Returns false (blocked) if unsynced records remain.
  Future<bool> clearAll() async {
    if (await pendingCount() > 0) return false;
    final isar = await AppDatabase.instance;
    await isar.writeTxn(() => isar.milkCollectionModels.clear());
    return true;
  }

  // ── Demo seeding ─────────────────────────────────────────────────────────

  /// Seed [demoTargetCount] dummy offline records spread across multiple
  /// sessions (dates) so no farmer appears twice in the same session.
  ///
  /// Blocked if any unsynced records already exist — call [clearAll] first
  /// (which also only works when pending = 0).
  ///
  /// [onProgress] receives (fraction 0.0–1.0, totalWritten) after each batch.
  Future<SeedResult> seedDummyCollections({
    required int routeId,
    required int shiftId,
    required int graderLocationId,
    required List<Map<String, dynamic>> farmers,
    void Function(double fraction, int written)? onProgress,
  }) async {
    if (farmers.isEmpty) {
      return SeedResult(written: 0, blocked: false, message: 'No farmers available');
    }

    // Block seeding if unsynced records exist — don't lose pending data
    final existingPending = await pendingCount();
    if (existingPending > 0) {
      return SeedResult(
        written: 0,
        blocked: true,
        message: '$existingPending unsynced record(s) still pending — sync first',
      );
    }

    final isar = await AppDatabase.instance;

    // How many sessions (distinct dates) we need so total >= demoTargetCount
    final sessionsNeeded = (demoTargetCount / farmers.length).ceil();
    final totalTarget    = sessionsNeeded * farmers.length;
    const batchSize      = 500;
    int   written        = 0;
    final now            = DateTime.now();
    final ts             = now.millisecondsSinceEpoch;

    final batch = <MilkCollectionModel>[];

    Future<void> _flush() async {
      if (batch.isEmpty) return;
      await isar.writeTxn(() async {
        for (final rec in batch) {
          await isar.milkCollectionModels.put(rec);
        }
      });
      written += batch.length;
      batch.clear();
      onProgress?.call(written / totalTarget, written);
    }

    // Grades cycle: A, A, B, A, C  (mostly A for realism)
    const grades = ['A', 'A', 'B', 'A', 'C'];

    for (var session = 0; session < sessionsNeeded; session++) {
      // Each session = a different past date (session 0 = today)
      final sessionDate = now.subtract(Duration(days: session));

      for (var fi = 0; fi < farmers.length; fi++) {
        final f = farmers[fi];
        final model = MilkCollectionModel()
          ..uuid             = 'demo-$ts-$session-$fi'
          ..farmerName       = f['name']?.toString() ?? 'Farmer ${fi + 1}'
          ..farmerServerId   = (f['serverId'] as int?) ?? 0
          ..routeId          = routeId
          ..shiftId          = shiftId
          ..graderLocationId = graderLocationId
          ..farmerId         = f['farmerCode']?.toString() ?? '${fi + 1}'
          ..weightKg         = 5.0 + ((fi % 20) * 1.5)      // 5–33.5 kg varied
          ..pricePerKg       = 45.0
          ..totalValue       = (5.0 + ((fi % 20) * 1.5)) * 45.0
          ..grade            = grades[fi % grades.length]
          ..notes            = 'Demo session ${session + 1}'
          ..collectedAt      = sessionDate.subtract(Duration(minutes: fi * 2))
          ..collectedBy      = 'grader'
          ..stationName      = 'Route $routeId'
          ..scaleDevice      = 'manual'
          ..isStableReading  = true
          ..synced           = false;
        batch.add(model);

        if (batch.length >= batchSize) {
          await _flush();
        }
      }
    }

    await _flush(); // remaining records

    return SeedResult(written: written, blocked: false,
        message: '$written demo records seeded across $sessionsNeeded sessions');
  }
}

class SeedResult {
  final int    written;
  final bool   blocked;
  final String message;
  const SeedResult({required this.written, required this.blocked, required this.message});
}
