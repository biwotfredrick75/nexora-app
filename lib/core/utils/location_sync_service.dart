import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/utils/providers.dart';

const _kQueueKey = 'location_queue';

/// Real-time GPS sync service.
/// - Streams position updates every time the device moves ≥ 10 m.
/// - Also fetches a fresh GPS fix every 2 min when stationary.
/// - Buffers positions in Hive when offline and flushes when connectivity returns.
class LocationSyncService {
  final WidgetRef _ref;
  final String _deviceIdentifier;
  final String _deviceType;

  bool _running = false;
  Position? _lastPosition;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _stationaryTimer;

  LocationSyncService(this._ref, this._deviceIdentifier, this._deviceType);

  static Future<bool> requestPermissions() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    // Upgrade to "always" so the stream works when the app is backgrounded
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
  }

  Future<void> start() async {
    if (_running) return;
    final granted = await requestPermissions();
    if (!granted) return;
    _running = true;

    // ── 1. Grab a quick coarse fix immediately (fast, works indoors) ──────────
    _pushQuickFix();

    // ── 2. Stream real-time movement updates (≥10 m OR every 5 s on Android) ──
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // minimum 10 m of movement
      ),
    ).listen(
      (pos) => _onPosition(pos),
      onError: (_) {},
    );

    // ── 3. Stationary heartbeat every 2 min — fetches a fresh GPS fix ───────
    _stationaryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _pushPeriodicFix();
    });

    // ── 4. Flush offline queue when connectivity returns ──────────────────────
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) _flushQueue();
    });
  }

  void stop() {
    _running = false;
    _positionSub?.cancel();
    _connectivitySub?.cancel();
    _stationaryTimer?.cancel();
    _positionSub = null;
    _connectivitySub = null;
    _stationaryTimer = null;
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  void _onPosition(Position pos) {
    if (!_running) return;
    _lastPosition = pos;
    _pushPayload(_buildPayload(pos));
  }

  /// Fast initial fix: try low accuracy first (< 2 s), then upgrade to high.
  Future<void> _pushQuickFix() async {
    try {
      // Low-accuracy gives a fast network/cell-tower fix
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      _lastPosition = pos;
      _pushPayload(_buildPayload(pos));
    } catch (_) {
      // Medium fix failed; the stream will deliver the first high-accuracy fix
    }
  }

  /// Periodic 2-min heartbeat: gets a fresh GPS fix so stationary devices
  /// still send real coordinates rather than repeating stale cached ones.
  Future<void> _pushPeriodicFix() async {
    if (!_running) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _lastPosition = pos;
      _pushPayload(_buildPayload(pos));
    } catch (_) {
      // If fresh fix times out, fall back to last known position
      if (_lastPosition != null) _pushPayload(_buildPayload(_lastPosition!));
    }
  }

  Map<String, dynamic> _buildPayload(Position pos) => {
    'identifier':  _deviceIdentifier,
    'device_type': _deviceType,
    'latitude':    pos.latitude,
    'longitude':   pos.longitude,
    'altitude':    pos.altitude,
    'speed':       pos.speed * 3.6,   // m/s → km/h
    'accuracy':    pos.accuracy,
    'fix_time':    DateTime.now().toUtc().toIso8601String(),
  };

  Future<void> _pushPayload(Map<String, dynamic> payload) async {
    final sent = await _trySend(payload);
    if (!sent) _enqueue(payload);
  }

  Future<bool> _trySend(Map<String, dynamic> payload) async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!results.any((r) => r != ConnectivityResult.none)) return false;
      final api = _ref.read(apiClientProvider);
      await api.post('/tracking/ingest', data: payload);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Offline queue ────────────────────────────────────────────────────────────

  void _enqueue(Map<String, dynamic> payload) {
    final box = Hive.box('app');
    final queue = List<Map>.from(box.get(_kQueueKey, defaultValue: <Map>[]));
    queue.add(payload);
    if (queue.length > 500) queue.removeRange(0, queue.length - 500);
    box.put(_kQueueKey, queue);
  }

  Future<void> _flushQueue() async {
    if (!_running) return;
    final box = Hive.box('app');
    final queue = List<Map>.from(box.get(_kQueueKey, defaultValue: <Map>[]));
    if (queue.isEmpty) return;
    final remaining = <Map>[];
    for (final item in queue) {
      final sent = await _trySend(Map<String, dynamic>.from(item));
      if (!sent) { remaining.addAll(queue.sublist(queue.indexOf(item))); break; }
    }
    box.put(_kQueueKey, remaining);
  }
}

final locationSyncProvider = Provider<LocationSyncService?>((ref) => null);
