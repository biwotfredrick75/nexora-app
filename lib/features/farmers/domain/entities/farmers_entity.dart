import 'package:equatable/equatable.dart';

/// Pure domain entity for Farmer.
/// No dependencies on Flutter, Isar, or Dio.
class FarmerEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FarmerEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
