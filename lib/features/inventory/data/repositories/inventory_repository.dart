import 'package:dartz/dartz.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:wakulima/core/database/app_database.dart';
import 'package:wakulima/core/database/models/inventory_item_model.dart';
import 'package:wakulima/core/database/models/sync_queue_model.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/network/api_result.dart';

class InventoryRepository {
  final ApiClient _api;
  static const _uuid = Uuid();

  InventoryRepository(this._api);

  Future<ApiResult<InventoryItemModel>> addItem({
    required String sku,
    required String name,
    required String category,
    required String unit,
    required double initialStock,
    required double minimumStock,
    required double unitCost,
    required double sellingPrice,
    required String location,
    String batchNumber = '',
    DateTime? expiryDate,
  }) async {
    final db = await AppDatabase.instance;
    final item = InventoryItemModel()
      ..uuid = _uuid.v4()
      ..sku = sku
      ..name = name
      ..category = category
      ..unit = unit
      ..currentStock = initialStock
      ..minimumStock = minimumStock
      ..unitCost = unitCost
      ..sellingPrice = sellingPrice
      ..location = location
      ..batchNumber = batchNumber
      ..expiryDate = expiryDate
      ..isActive = true
      ..updatedAt = DateTime.now()
      ..synced = false;

    try {
      await db.writeTxn(() async => db.inventoryItemModels.put(item));
      return Right(item);
    } catch (e) {
      return Left(CacheFailure('Failed to add item: $e'));
    }
  }

  Future<ApiResult<void>> adjustStock({
    required String uuid,
    required double adjustment, // positive = in, negative = out
    required String reason,
  }) async {
    final db = await AppDatabase.instance;
    final item =
        await db.inventoryItemModels.filter().uuidEqualTo(uuid).findFirst();
    if (item == null) return Left(const CacheFailure('Item not found'));

    item.currentStock += adjustment;
    item.updatedAt = DateTime.now();
    item.synced = false;

    if (item.currentStock < 0) {
      return Left(const ValidationFailure('Insufficient stock'));
    }

    try {
      await db.writeTxn(() async => db.inventoryItemModels.put(item));
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to adjust stock: $e'));
    }
  }

  Future<List<InventoryItemModel>> getLowStockItems() async {
    final db = await AppDatabase.instance;
    final all =
        await db.inventoryItemModels.filter().isActiveEqualTo(true).findAll();
    return all.where((i) => i.isLowStock).toList();
  }

  Future<List<InventoryItemModel>> getByCategory(String category) async {
    final db = await AppDatabase.instance;
    return db.inventoryItemModels
        .filter()
        .categoryEqualTo(category)
        .isActiveEqualTo(true)
        .sortByName()
        .findAll();
  }

  Future<double> getTotalStockValue() async {
    final db = await AppDatabase.instance;
    final items =
        await db.inventoryItemModels.filter().isActiveEqualTo(true).findAll();
    return items.fold<double>(0.0, (s, i) => s + (i.stockValue));
  }
}
