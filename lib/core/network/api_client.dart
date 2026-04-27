import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/router/app_router.dart' show authNotifier;
import 'package:wakulima/core/utils/app_constants.dart';

class ApiClient {
  late final Dio _dio;

  static String get baseUrl => '${AppConstants.apiBaseUrl}/api';

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-App-Version': '3.1.118',
        'ngrok-skip-browser-warning': 'true',
      },
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(),
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => print('[APIS] $obj'),
      ),
    ]);
  }

  Dio get dio => _dio;

  // Generic methods
  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);
}

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = Hive.box('auth').get('token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      Hive.box('auth').clear();
      authNotifier.onChange();
    }
    handler.next(err);
  }
}

class _RetryInterceptor extends Interceptor {
  final Dio dio;
  _RetryInterceptor(this.dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err)) {
      try {
        await Future.delayed(const Duration(seconds: 2));
        final response = await dio.request(
          err.requestOptions.path,
          options: Options(method: err.requestOptions.method),
          data: err.requestOptions.data,
          queryParameters: err.requestOptions.queryParameters,
        );
        handler.resolve(response);
        return;
      } catch (_) {}
    }
    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.response?.statusCode == 503;
  }
}
