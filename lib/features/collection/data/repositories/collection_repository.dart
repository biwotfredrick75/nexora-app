import 'package:dartz/dartz.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/milk_collection_model.dart';
import 'package:wakulima/core/database/models/sync_queue_model.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/network/api_result.dart';

class CollectionRepository {
  final ApiClient _api;
  static const _uuid = Uuid();

  CollectionRepository(this._api);

  /// Record a milk collection.
  /// Always writes to Isar first, then queues for sync.
  Future<ApiResult<MilkCollectionModel>> recordCollection({
    required String farmerName,
    required String farmerId,
    required double weightKg,
    required double pricePerKg,
    required String grade,
    required String notes,
    required String scaleDevice,
    required bool isStableReading,
    required String collectedBy,
    required String stationName,
  }) async {
    final db = await AppDatabase.instance;
    final record = MilkCollectionModel()
      ..uuid = _uuid.v4()
      ..farmerName = farmerName
      ..farmerId = farmerId
      ..weightKg = weightKg
      ..pricePerKg = pricePerKg
      ..totalValue = weightKg * pricePerKg
      ..grade = grade
      ..notes = notes
      ..collectedAt = DateTime.now()
      ..collectedBy = collectedBy
      ..stationName = stationName
      ..scaleDevice = scaleDevice
      ..isStableReading = isStableReading
      ..synced = false;

    try {
      // 1. Write locally first — always succeeds
      await db.writeTxn(() async => db.milkCollectionModels.put(record));

      // 2. Queue for cloud sync
      await _queueSync(
          db, 'create', 'milk_collection', record.uuid, _toJson(record));

      return Right(record);
    } catch (e) {
      return Left(CacheFailure('Failed to save collection: $e'));
    }
  }

  /// Get today's collections
  Future<List<MilkCollectionModel>> getTodayCollections() async {
    final db = await AppDatabase.instance;
    final start =
        DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
    final end = start.add(const Duration(days: 1));
    return db.milkCollectionModels
        .filter()
        .collectedAtBetween(start, end)
        .sortByCollectedAtDesc()
        .findAll();
  }

  /// Get collections for a specific date range
  Future<List<MilkCollectionModel>> getCollections({
    required DateTime from,
    required DateTime to,
    String? farmerName,
  }) async {
    final db = await AppDatabase.instance;
    var query = db.milkCollectionModels.filter().collectedAtBetween(from, to);
    if (farmerName != null) {
      query = query.farmerNameContains(farmerName, caseSensitive: false);
    }
    return query.sortByCollectedAtDesc().findAll();
  }

  /// Today's totals
  Future<Map<String, double>> getTodayTotals() async {
    final records = await getTodayCollections();
    final totalKg = records.fold(0.0, (s, r) => s + r.weightKg);
    final totalValue = records.fold(0.0, (s, r) => s + r.totalValue);
    return {
      'total_kg': totalKg,
      'total_value': totalValue,
      'count': records.length.toDouble()
    };
  }

  Future<void> _queueSync(dynamic db, String op, String entity, String uuid,
      Map<String, dynamic> payload) async {
    final queue = SyncQueueModel()
      ..operationType = op
      ..entityType = entity
      ..entityUuid = uuid
      ..payloadJson = payload.toString()
      ..attempts = 0
      ..maxAttempts = 5
      ..processed = false
      ..createdAt = DateTime.now();
    await db.writeTxn(() async => db.syncQueueModels.put(queue));
  }

  Map<String, dynamic> _toJson(MilkCollectionModel m) => {
        'uuid': m.uuid,
        'farmer_name': m.farmerName,
        'farmer_id': m.farmerId,
        'weight_kg': m.weightKg,
        'price_per_kg': m.pricePerKg,
        'total_value': m.totalValue,
        'grade': m.grade,
        'notes': m.notes,
        'collected_at': m.collectedAt.toIso8601String(),
        'collected_by': m.collectedBy,
        'station_name': m.stationName,
        'scale_device': m.scaleDevice,
        'is_stable_reading': m.isStableReading,
      };
}
