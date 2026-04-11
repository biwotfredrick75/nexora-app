import 'package:dartz/dartz.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/sale_model.dart';
import 'package:wakulima/core/database/models/sync_queue_model.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/network/api_result.dart';
import 'dart:convert';

class SalesRepository {
  final ApiClient _api;
  static const _uuid = Uuid();

  SalesRepository(this._api);

  Future<ApiResult<SaleModel>> createSale({
    required String customerName,
    required String customerId,
    required String customerPhone,
    required List<Map<String, dynamic>> lineItems,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String paymentMethod,
    required double amountPaid,
    required String createdBy,
    required String stationName,
  }) async {
    final db = await AppDatabase.instance;

    final invoiceNumber = _generateInvoiceNumber();
    final sale = SaleModel()
      ..uuid = _uuid.v4()
      ..invoiceNumber = invoiceNumber
      ..customerName = customerName
      ..customerId = customerId
      ..customerPhone = customerPhone
      ..lineItemsJson = lineItems.map((i) => jsonEncode(i)).toList()
      ..subtotal = subtotal
      ..discount = discount
      ..tax = tax
      ..total = total
      ..paymentMethod = paymentMethod
      ..amountPaid = amountPaid
      ..status = amountPaid >= total ? 'paid' : 'confirmed'
      ..saleDate = DateTime.now()
      ..createdBy = createdBy
      ..stationName = stationName
      ..synced = false;

    try {
      await db.writeTxn(() async => db.saleModels.put(sale));
      await _queueSync(db, 'create', 'sale', sale.uuid, sale);
      return Right(sale);
    } catch (e) {
      return Left(CacheFailure('Failed to save sale: $e'));
    }
  }

  Future<List<SaleModel>> getSales({
    String? status,
    DateTime? from,
    DateTime? to,
    String? customerName,
  }) async {
    final db = await AppDatabase.instance;
    var query = db.saleModels.filter();

    if (status != null) {
      return db.saleModels
          .filter()
          .statusEqualTo(status)
          .sortBySaleDateDesc()
          .findAll();
    }

    if (from != null && to != null) {
      return db.saleModels
          .filter()
          .saleDateBetween(from, to)
          .sortBySaleDateDesc()
          .findAll();
    }

    return [];
  }

  Future<ApiResult<SaleModel>> updateSaleStatus(
      String uuid, String status) async {
    final db = await AppDatabase.instance;
    final sale = await db.saleModels.filter().uuidEqualTo(uuid).findFirst();
    if (sale == null) return Left(const CacheFailure('Sale not found'));

    sale.status = status;
    try {
      await db.writeTxn(() async => db.saleModels.put(sale));
      await _queueSync(db, 'update', 'sale', uuid, sale);
      return Right(sale);
    } catch (e) {
      return Left(CacheFailure('Failed to update sale: $e'));
    }
  }

  Future<Map<String, dynamic>> getTodaySummary() async {
    final db = await AppDatabase.instance;
    final start =
        DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
    final end = start.add(const Duration(days: 1));
    final sales =
        await db.saleModels.filter().saleDateBetween(start, end).findAll();

    return {
      'count': sales.length,
      'total': sales.fold(0.0, (s, e) => s + e.total),
      'paid': sales.where((s) => s.status == 'paid').length,
      'pending': sales.where((s) => s.status == 'confirmed').length,
      'collected': sales.fold(0.0, (s, e) => s + e.amountPaid),
    };
  }

  String _generateInvoiceNumber() {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rand =
        (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return 'INV-$ts-$rand';
  }

  Future<void> _queueSync(dynamic db, String op, String entity, String uuid,
      dynamic payload) async {
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
}
