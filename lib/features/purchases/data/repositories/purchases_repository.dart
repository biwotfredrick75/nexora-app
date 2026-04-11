import 'package:dartz/dartz.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/purchase_model.dart';
import 'package:wakulima/core/database/models/sync_queue_model.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/network/api_result.dart';
import 'dart:convert';

class PurchasesRepository {
  final ApiClient _api;
  static const _uuid = Uuid();

  PurchasesRepository(this._api);

  Future<ApiResult<PurchaseModel>> createPurchaseOrder({
    required String supplierName,
    required String supplierId,
    required String supplierPhone,
    required List<Map<String, dynamic>> lineItems,
    required double subtotal,
    required double tax,
    required double total,
    required String createdBy,
  }) async {
    final db = await AppDatabase.instance;
    final po = PurchaseModel()
      ..uuid = _uuid.v4()
      ..poNumber = _generatePONumber()
      ..supplierName = supplierName
      ..supplierId = supplierId
      ..supplierPhone = supplierPhone
      ..lineItemsJson = lineItems.map((i) => jsonEncode(i)).toList()
      ..subtotal = subtotal
      ..tax = tax
      ..total = total
      ..amountPaid = 0
      ..status = 'draft'
      ..orderDate = DateTime.now()
      ..createdBy = createdBy
      ..grnCreated = false
      ..synced = false;

    try {
      await db.writeTxn(() async => db.purchaseModels.put(po));
      await _queueSync(db, po);
      return Right(po);
    } catch (e) {
      return Left(CacheFailure('Failed to create purchase order: $e'));
    }
  }

  Future<ApiResult<void>> receiveGoods({
    required String uuid,
    required String grnNumber,
    required DateTime receivedDate,
  }) async {
    final db = await AppDatabase.instance;
    final po = await db.purchaseModels.filter().uuidEqualTo(uuid).findFirst();
    if (po == null) return Left(const CacheFailure('Purchase order not found'));

    po.status = 'received';
    po.receivedDate = receivedDate;
    po.grnCreated = true;
    po.grnNumber = grnNumber;
    po.synced = false;

    try {
      await db.writeTxn(() async => db.purchaseModels.put(po));
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to receive goods: $e'));
    }
  }

  Future<List<PurchaseModel>> getPurchases({String? status}) async {
    final db = await AppDatabase.instance;
    if (status != null) {
      return db.purchaseModels
          .filter()
          .statusEqualTo(status)
          .sortByOrderDateDesc()
          .findAll();
    }
    return [];
    // db.purchaseModels.filter().sortByOrderDateDesc().limit(100).findAll();
  }

  String _generatePONumber() {
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final rand = (now.millisecondsSinceEpoch % 1000).toString().padLeft(3, '0');
    return 'PO-$ts-$rand';
  }

  Future<void> _queueSync(dynamic db, PurchaseModel po) async {
    final queue = SyncQueueModel()
      ..operationType = 'create'
      ..entityType = 'purchase'
      ..entityUuid = po.uuid
      ..payloadJson = po.toString()
      ..attempts = 0
      ..maxAttempts = 5
      ..processed = false
      ..createdAt = DateTime.now();
    await db.writeTxn(() async => db.syncQueueModels.put(queue));
  }
}
