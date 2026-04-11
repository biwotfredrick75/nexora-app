import 'package:equatable/equatable.dart';

/// Pure domain entity for QualityTest.
/// No dependencies on Flutter, Isar, or Dio.
class QualityTestEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QualityTestEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
