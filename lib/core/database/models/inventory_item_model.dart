import 'package:isar/isar.dart';
part 'inventory_item_model.g.dart';

@collection
class InventoryItemModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  @Index()
  late String sku;

  @Index()
  late String name;

  late String category; // raw_milk, processed, packaging, feed, vet, other
  late String unit; // litres, kg, pieces, bags
  late double currentStock;
  late double minimumStock; // triggers low-stock alert
  late double unitCost;
  late double sellingPrice;

  late String location; // warehouse, cold_room, shop
  late String batchNumber;
  DateTime? expiryDate;

  @Index()
  late bool isActive;
  late DateTime updatedAt;
  late bool synced;

  @ignore
  bool get isLowStock => currentStock <= minimumStock;

  @ignore
  double get stockValue => currentStock * unitCost;
}
