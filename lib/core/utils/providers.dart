import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/ble/ble_scale_service.dart';
import 'package:wakulima/core/sync/sync_engine.dart';
import 'package:wakulima/features/auth/data/auth_api_service.dart';
import 'package:wakulima/features/collection/data/repositories/collection_repository.dart';
import 'package:wakulima/features/esp/data/repositories/esp_repository.dart';

// ─── Core Services ─────────────────────────────────────────────────────────

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authApiServiceProvider = Provider<AuthApiService>(
  (ref) => AuthApiService(ref.watch(apiClientProvider)),
);

final bleScaleServiceProvider = Provider<BleScaleService>((ref) {
  final svc = BleScaleService();
  ref.onDispose(svc.dispose);
  return svc;
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine();
  engine.init();
  ref.onDispose(engine.dispose);
  return engine;
});

// ─── Repositories ─────────────────────────────────────────────────────────

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return CollectionRepository(ref.watch(apiClientProvider));
});

final espRepositoryProvider = Provider<EspRepository>((ref) {
  return EspRepository(ref.watch(apiClientProvider));
});

// ─── BLE State ────────────────────────────────────────────────────────────

final bleStateProvider = StreamProvider((ref) {
  return ref.watch(bleScaleServiceProvider).stateStream;
});

final bleWeightProvider = StreamProvider((ref) {
  return ref.watch(bleScaleServiceProvider).weightStream;
});

final bleDeviceNameProvider = StreamProvider<String>((ref) {
  return ref.watch(bleScaleServiceProvider).deviceNameStream;
});

// ─── Sync State ───────────────────────────────────────────────────────────

final syncStatusProvider = StreamProvider((ref) {
  return ref.watch(syncEngineProvider).statusStream;
});

// ─── Collection form data (routes + shifts from API) ─────────────────────

final collectionFormDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final auth = ref.watch(authApiServiceProvider);
  return await auth.fetchCollectionFormData() ?? {};
});

// ─── App module config (enabled modules from ERP) ────────────────────────
// StreamProvider polls every 15 s so disabling a module in the ERP is
// reflected in the app within one polling cycle.  Invalidating the provider
// (e.g. on app-foreground) triggers an immediate re-fetch.

final enabledModuleIdsProvider = StreamProvider<Set<String>>((ref) async* {
  Future<Set<String>> _fetch() async {
    try {
      final res = await ref.read(apiClientProvider).get('/setup/app-modules');
      final body = res.data as Map<String, dynamic>;
      final data = body['data'];
      if (data is List) {
        return data
            .where((m) => (m as Map)['is_enabled'] == true)
            .map((m) => (m as Map)['module_id'].toString())
            .toSet();
      }
    } catch (_) {}
    return <String>{};  // fail-open: show all modules
  }

  // Emit immediately so the grid renders without waiting for the first tick.
  yield await _fetch();

  // Then re-fetch every 15 seconds.
  await for (final _ in Stream.periodic(const Duration(seconds: 15))) {
    yield await _fetch();
  }
});

// ─── Today's collection stats ─────────────────────────────────────────────

final todayStatsProvider = FutureProvider<Map<String, double>>((ref) async {
  final repo = ref.watch(collectionRepositoryProvider);
  return repo.getTodayTotals();
});

final todayCollectionsProvider = FutureProvider((ref) async {
  final repo = ref.watch(collectionRepositoryProvider);
  return repo.getTodayCollections();
});
