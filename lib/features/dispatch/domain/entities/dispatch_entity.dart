import 'package:equatable/equatable.dart';

/// Pure domain entity for DispatchOrder.
/// No dependencies on Flutter, Isar, or Dio.
class DispatchOrderEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DispatchOrderEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
