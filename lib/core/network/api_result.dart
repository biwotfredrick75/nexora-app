import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

// Failure types
abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure(super.message, {this.statusCode});
}

class NetworkFailure extends Failure {
  const NetworkFailure() : super('No internet connection. Working offline.');
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class ValidationFailure extends Failure {
  final Map<String, List<String>> errors;
  const ValidationFailure(super.message, {this.errors = const {}});
}

class AuthFailure extends Failure {
  const AuthFailure() : super('Session expired. Please sign in again.');
}

// Type alias
typedef ApiResult<T> = Either<Failure, T>;

// Helper to wrap Dio calls safely
Future<ApiResult<T>> safeApiCall<T>(Future<T> Function() call) async {
  try {
    final result = await call();
    return Right(result);
  } on DioException catch (e) {
    return Left(_mapDioError(e));
  } catch (e) {
    return Left(ServerFailure(e.toString()));
  }
}

Failure _mapDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return const NetworkFailure();
    case DioExceptionType.connectionError:
      return const NetworkFailure();
    default:
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) return const AuthFailure();
      if (statusCode == 422) {
        final errors = e.response?.data['errors'] as Map<String, dynamic>? ?? {};
        return ValidationFailure(
          e.response?.data['message'] ?? 'Validation error',
          errors: errors.map((k, v) => MapEntry(k, List<String>.from(v))),
        );
      }
      return ServerFailure(
        e.response?.data?['message'] ?? 'Server error',
        statusCode: statusCode,
      );
  }
}
