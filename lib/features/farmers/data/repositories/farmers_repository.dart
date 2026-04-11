import 'package:dartz/dartz.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/farmer_model.dart';
import 'package:wakulima/core/database/models/sync_queue_model.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/network/api_result.dart';

class FarmersRepository {
  final ApiClient _api;
  static const _uuid = Uuid();

  FarmersRepository(this._api);

  Future<ApiResult<FarmerModel>> registerFarmer({
    required String name,
    required String farmerCode,
    required String phone,
    required String nationalId,
    required String location,
    required String county,
    required String ward,
    required String paymentMethod,
    String mpesaNumber = '',
    String bankName = '',
    String bankAccount = '',
  }) async {
    final db = await AppDatabase.instance;
    final farmer = FarmerModel()
      ..uuid = _uuid.v4()
      ..name = name
      ..farmerCode = farmerCode
      ..phone = phone
      ..nationalId = nationalId
      ..location = location
      ..county = county
      ..ward = ward
      ..paymentMethod = paymentMethod
      ..mpesaNumber = mpesaNumber
      ..bankName = bankName
      ..bankAccount = bankAccount
      ..totalKgDelivered = 0
      ..totalEarnings = 0
      ..deliveryCount = 0
      ..isActive = true
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now()
      ..synced = false;

    try {
      await db.writeTxn(() async => db.farmerModels.put(farmer));
      await _queueSync(db, farmer);
      return Right(farmer);
    } catch (e) {
      return Left(CacheFailure('Failed to register farmer: $e'));
    }
  }

  Future<List<FarmerModel>> searchFarmers(String query) async {
    final db = await AppDatabase.instance;
    if (query.isEmpty) {
      return db.farmerModels
          .filter()
          .isActiveEqualTo(true)
          .sortByName()
          .limit(50)
          .findAll();
    }
    return db.farmerModels
        .filter()
        .nameContains(query, caseSensitive: false)
        .or()
        .farmerCodeContains(query, caseSensitive: false)
        .or()
        .phoneContains(query)
        .sortByName()
        .limit(30)
        .findAll();
  }

  Future<FarmerModel?> getByCode(String code) async {
    final db = await AppDatabase.instance;
    return db.farmerModels.filter().farmerCodeEqualTo(code).findFirst();
  }

  Future<void> _queueSync(dynamic db, FarmerModel farmer) async {
    final queue = SyncQueueModel()
      ..operationType = 'create'
      ..entityType = 'farmer'
      ..entityUuid = farmer.uuid
      ..payloadJson = farmer.toString()
      ..attempts = 0
      ..maxAttempts = 5
      ..processed = false
      ..createdAt = DateTime.now();
    await db.writeTxn(() async => db.syncQueueModels.put(queue));
  }
}
