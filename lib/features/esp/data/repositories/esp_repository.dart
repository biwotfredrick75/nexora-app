// ESP (External Agrovets & Service Providers) — invoicing farmers, employees
// and transporters (= graders). Credit limits are a live, contested resource
// shared across devices, so unlike collection this is online-only — no
// offline queue/Isar cache. See EspController on the backend for the API.
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/network/api_client.dart';

class EspRepository {
  final ApiClient _api;
  EspRepository(this._api);

  List<Map<String, dynamic>> _toList(dynamic data) {
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// The ESP provider linked to this login (cached at login), if any. Only
  /// agrovet/service-provider accounts have one — the backend enforces this
  /// server-side too, this is just for the UI to lock/auto-select the picker.
  Map<String, dynamic>? getLinkedProvider() {
    final raw = Hive.box('auth').get('esp_provider');
    return raw != null ? Map<String, dynamic>.from(raw as Map) : null;
  }

  Future<List<Map<String, dynamic>>> getProviders() async {
    final res = await _api.get('/esp/providers', params: {'status': 'active'});
    return _toList((res.data as Map<String, dynamic>)['data']);
  }

  /// Parties billable for the given [partyType]. Farmers come from the
  /// grader's own cached route list (Hive `auth.farmers`, set at login);
  /// employees/transporters hit the live backend lookup.
  Future<List<Map<String, dynamic>>> getParties(String partyType, {String? search}) async {
    if (partyType == 'farmer') {
      final raw = Hive.box('auth').get('farmers') as List?;
      final farmers = (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (search == null || search.isEmpty) return farmers;
      final q = search.toLowerCase();
      return farmers.where((f) =>
          (f['full_name'] ?? '').toString().toLowerCase().contains(q) ||
          (f['farmer_no'] ?? '').toString().toLowerCase().contains(q)).toList();
    }

    final res = await _api.get('/esp/parties', params: {
      'party_type': partyType,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return _toList((res.data as Map<String, dynamic>)['data']);
  }

  Future<Map<String, dynamic>> getCreditScore(String partyType, int partyId) async {
    final res = await _api.get('/esp/credit-score', params: {
      'party_type': partyType,
      'party_id': partyId.toString(),
    });
    return Map<String, dynamic>.from((res.data as Map<String, dynamic>)['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> getSales({String? partyType, int? partyId, String? status}) async {
    final res = await _api.get('/esp/sales', params: {
      if (partyType != null) 'party_type': partyType,
      if (partyId != null) 'party_id': partyId.toString(),
      if (status != null) 'status': status,
    });
    return _toList((res.data as Map<String, dynamic>)['data']);
  }

  Future<Map<String, dynamic>> getSale(int id) async {
    final res = await _api.get('/esp/sales/$id');
    return Map<String, dynamic>.from((res.data as Map<String, dynamic>)['data'] as Map);
  }

  Future<Map<String, dynamic>> createSale({
    required int espId,
    required String partyType,
    required int partyId,
    required String saleDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _api.post('/esp/sales', data: {
      'esp_id': espId,
      'party_type': partyType,
      'party_id': partyId,
      'sale_date': saleDate,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'items': items,
    });
    return Map<String, dynamic>.from((res.data as Map<String, dynamic>)['data'] as Map);
  }

  Future<Map<String, dynamic>> updateSale(int id, {
    String? saleDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _api.put('/esp/sales/$id', data: {
      if (saleDate != null) 'sale_date': saleDate,
      if (notes != null) 'notes': notes,
      'items': items,
    });
    return Map<String, dynamic>.from((res.data as Map<String, dynamic>)['data'] as Map);
  }

  Future<void> voidSale(int id) async {
    await _api.post('/esp/sales/$id/void');
  }

  Future<Map<String, dynamic>> adjustSale(int id, {required double deltaAmount, required String reason}) async {
    final res = await _api.post('/esp/sales/$id/adjust', data: {
      'delta_amount': deltaAmount,
      'reason': reason,
    });
    return Map<String, dynamic>.from((res.data as Map<String, dynamic>)['data'] as Map);
  }
}
