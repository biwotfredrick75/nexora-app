import 'package:equatable/equatable.dart';

/// Pure domain entity for DairyRecord.
/// No dependencies on Flutter, Isar, or Dio.
class DairyRecordEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DairyRecordEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
