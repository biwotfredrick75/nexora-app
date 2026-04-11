import 'package:equatable/equatable.dart';

/// Pure domain entity for MilkCollection.
/// No dependencies on Flutter, Isar, or Dio.
class MilkCollectionEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MilkCollectionEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
