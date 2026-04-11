import 'package:equatable/equatable.dart';

/// Pure domain entity for Driver.
/// No dependencies on Flutter, Isar, or Dio.
class DriverEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DriverEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
