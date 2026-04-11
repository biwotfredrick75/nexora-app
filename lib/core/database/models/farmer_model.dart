import 'package:isar/isar.dart';
part 'farmer_model.g.dart';

@collection
class FarmerModel {
  Id id = Isar.autoIncrement;

  /// Backend farmer ID (farmers.id) — used when syncing collections
  @Index(unique: true)
  int? serverId;

  /// Backend route ID — used to filter farmers by grader's route
  @Index()
  int? routeId;

  @Index(unique: true)
  late String uuid;

  @Index()
  late String name;

  @Index(unique: true)
  late String farmerCode;

  late String phone;
  late String nationalId;
  late String location;
  late String county;
  late String ward;

  // Payment
  late String paymentMethod; // mpesa, bank, cash
  late String mpesaNumber;
  late String bankName;
  late String bankAccount;

  // Stats
  late double totalKgDelivered;
  late double totalEarnings;
  late int deliveryCount;

  @Index()
  late bool isActive;
  late DateTime createdAt;
  late DateTime updatedAt;
  late bool synced;
}
