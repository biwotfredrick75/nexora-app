import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakulima/core/database/models/milk_collection_model.dart';
import 'package:wakulima/core/database/models/farmer_model.dart';
import 'package:wakulima/core/database/models/sale_model.dart';
import 'package:wakulima/core/database/models/purchase_model.dart';
import 'package:wakulima/core/database/models/inventory_item_model.dart';
import 'package:wakulima/core/database/models/sync_queue_model.dart';

class AppDatabase {
  static Isar? _isar;

  static Future<Isar> get instance async {
    if (_isar != null && _isar!.isOpen) return _isar!;
    return await _init();
  }

  static Future<Isar> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        MilkCollectionModelSchema,
        FarmerModelSchema,
        SaleModelSchema,
        PurchaseModelSchema,
        InventoryItemModelSchema,
        SyncQueueModelSchema,
      ],
      directory: dir.path,
      name: 'wakulima_db',
      inspector: false, // disable inspector in production
    );
    return _isar!;
  }

  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
