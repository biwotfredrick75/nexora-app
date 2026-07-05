import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/database/farmers_local_repository.dart';
import 'package:wakulima/core/network/api_client.dart';

class AuthApiService {
  final ApiClient _api;
  AuthApiService(this._api);

  /// Grader login via loc_code + password.
  /// Hits POST /api/grader/login — Flutter/mobile-only endpoint.
  /// Returns error message, or null on success.
  Future<String?> login(String locCode, String password) async {
    try {
      final res = await _api.post('/grader/login', data: {
        'loc_code': locCode.trim(),
        'password': password,
      });

      final body = res.data as Map<String, dynamic>;
      if (body['success'] != true) {
        return body['message'] as String? ?? 'Login failed';
      }

      final data   = body['data'] as Map<String, dynamic>;
      final token  = data['token'] as String;
      final grader = data['grader'] as Map<String, dynamic>;
      final route  = data['route'];
      final farmers = data['farmers'];

      final box = Hive.box('auth');
      await box.put('token', token);
      await box.put('user', {
        'id':            grader['id'],
        'loc_code':      grader['loc_code'],
        'location_id':   grader['location_id'],
        'location_code': grader['location_code'],
        'name':          grader['name'],
        'roles':         (grader['roles'] as List?)?.join(',') ?? '',
      });
      if (route != null) {
        await box.put('route', route);
      }
      if (farmers != null) {
        await box.put('farmers', farmers);
        // Also persist to Isar for fast offline access
        if (route != null) {
          final routeId = (route['id'] as num?)?.toInt() ?? 0;
          if (routeId > 0) {
            await FarmersLocalRepository().saveFromLogin(
              farmers as List<dynamic>,
              routeId,
            );
          }
        }
      }

      return null; // success
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return 'Invalid location code or password';
      if (e.response?.statusCode == 422) {
        final errors = e.response?.data?['errors'];
        if (errors is Map) return errors.values.first?.first?.toString();
        return e.response?.data?['message']?.toString() ?? 'Validation error';
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return 'Cannot reach server. Check your connection.';
      }
      return e.response?.data?['message']?.toString() ?? 'Login failed';
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  /// Logout — revoke token on server, clear local session.
  Future<void> logout() async {
    try {
      await _api.post('/grader/logout');
    } catch (_) {}
    await Hive.box('auth').clear();
  }

  /// Fetch form data needed for milk collection (routes + shifts).
  /// On success the data is cached in Hive so it is available offline.
  Future<Map<String, dynamic>?> fetchCollectionFormData() async {
    final box = Hive.box('auth');
    try {
      final res = await _api.get('/farmers/milk-purchases/form-data');
      final body = res.data as Map<String, dynamic>;
      if (body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        await box.put('form_data', data);
        return data;
      }
    } catch (_) {}
    // Offline fallback — return last cached form data
    final cached = box.get('form_data');
    if (cached is Map) return Map<String, dynamic>.from(cached);
    return null;
  }

  /// Fetch farmers for a given route.
  /// Persists both route and farmers to Hive + Isar so offline access works.
  Future<List<Map<String, dynamic>>> getFarmersByRoute(int routeId) async {
    try {
      final res = await _api.get('/farmers/routes/$routeId/farmers');
      final body = res.data as Map<String, dynamic>;
      if (body['success'] == true) {
        final data    = body['data'] as Map<String, dynamic>;
        final farmers = List<Map<String, dynamic>>.from(data['farmers'] as List);
        final route   = data['route'];

        // Persist so offline access + sync engine have what they need
        final box = Hive.box('auth');
        if (route != null) await box.put('route', route);
        await box.put('farmers', farmers);

        if (route != null) {
          final rid = (route['id'] as num?)?.toInt() ?? 0;
          if (rid > 0) {
            await FarmersLocalRepository().saveFromLogin(farmers, rid);
          }
        }

        return farmers;
      }
    } catch (_) {}
    return [];
  }
}
