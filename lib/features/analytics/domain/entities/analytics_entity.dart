import 'package:equatable/equatable.dart';

/// Pure domain entity for AnalyticsReport.
/// No dependencies on Flutter, Isar, or Dio.
class AnalyticsReportEntity extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AnalyticsReportEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, createdAt, updatedAt];
}
