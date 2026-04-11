import 'package:isar/isar.dart';
part 'milk_collection_model.g.dart';

@collection
class MilkCollectionModel {
  Id id = Isar.autoIncrement;

  @Index()
  late String uuid;

  @Index()
  late String farmerName;

  /// Backend farmer ID (int) — used when POSTing to /farmers/milk-purchases
  int? farmerServerId;

  /// Backend route ID
  int? routeId;

  /// Backend shift ID
  int? shiftId;

  /// Backend grader location ID
  int? graderLocationId;

  late String farmerId;
  late double weightKg;
  late double pricePerKg;
  late double totalValue;
  late String grade; // A, B, C
  late String notes;

  @Index()
  late DateTime collectedAt;
  late String collectedBy;
  late String stationName;

  // BLE metadata
  late String scaleDevice;
  late bool isStableReading;

  // Sync
  @Index()
  late bool synced;
  DateTime? syncedAt;

  @ignore
  double get computedValue => weightKg * pricePerKg;
}
