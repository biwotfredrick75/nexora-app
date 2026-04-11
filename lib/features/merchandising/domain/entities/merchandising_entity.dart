import 'package:equatable/equatable.dart';

/// Pure domain entity for MerchandisingActivity.
/// No dependencies on Flutter, Isar, or Dio.
class MerchandisingActivityEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MerchandisingActivityEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
