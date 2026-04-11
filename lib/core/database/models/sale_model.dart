import 'package:isar/isar.dart';
part 'sale_model.g.dart';

@collection
class SaleModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  @Index()
  late String invoiceNumber;

  @Index()
  late String customerName;
  late String customerId;
  late String customerPhone;

  late List<String> lineItemsJson; // JSON-encoded list of SaleLineItem
  late double subtotal;
  late double discount;
  late double tax;
  late double total;

  late String paymentMethod; // cash, mpesa, credit
  late double amountPaid;

  @Index()
  late String status; // draft, confirmed, paid, cancelled

  @Index()
  late DateTime saleDate;
  late String createdBy;
  late String stationName;

  late bool synced;
  DateTime? syncedAt;
}
