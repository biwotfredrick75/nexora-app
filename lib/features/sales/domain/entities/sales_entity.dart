import 'package:equatable/equatable.dart';

/// Pure domain entity for Sale.
/// No dependencies on Flutter, Isar, or Dio.
class SaleEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SaleEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
