import 'package:isar/isar.dart';
part 'sync_queue_model.g.dart';

/// Every offline write is queued here.
/// SyncEngine reads this table and flushes to the API.
@collection
class SyncQueueModel {
  Id id = Isar.autoIncrement;

  @Index()
  late String operationType; // create, update, delete

  @Index()
  late String entityType; // milk_collection, sale, purchase, farmer, inventory

  late String entityUuid;
  late String payloadJson; // JSON of the entity

  @Index()
  late int attempts;
  late int maxAttempts;

  @Index()
  late bool processed;

  String? lastError;

  @Index()
  late DateTime createdAt;
  DateTime? processedAt;
}
