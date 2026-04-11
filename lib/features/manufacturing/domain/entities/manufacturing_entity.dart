import 'package:equatable/equatable.dart';

/// Pure domain entity for ProductionBatch.
/// No dependencies on Flutter, Isar, or Dio.
class ProductionBatchEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductionBatchEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
