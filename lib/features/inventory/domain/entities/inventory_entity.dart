import 'package:equatable/equatable.dart';

/// Pure domain entity for InventoryItem.
/// No dependencies on Flutter, Isar, or Dio.
class InventoryItemEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryItemEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
