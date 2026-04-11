import 'package:isar/isar.dart';
part 'purchase_model.g.dart';

@collection
class PurchaseModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  @Index()
  late String poNumber; // Purchase Order number

  @Index()
  late String supplierName;
  late String supplierId;
  late String supplierPhone;

  late List<String> lineItemsJson;
  late double subtotal;
  late double tax;
  late double total;
  late double amountPaid;

  @Index()
  late String status; // draft, ordered, received, partial, cancelled

  late DateTime orderDate;
  DateTime? receivedDate;
  late String createdBy;

  // GRN (Goods Received Note)
  late bool grnCreated;
  String? grnNumber;

  late bool synced;
  DateTime? syncedAt;
}
