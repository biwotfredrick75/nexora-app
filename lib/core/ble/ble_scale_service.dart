import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ── Known scale service / characteristic UUIDs ────────────────────────────────

/// HM-10 BLE module — T-Scale A12, T7E, CS and many Chinese OEM scales.
const _hm10ServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const _hm10CharUuid    = '0000ffe1-0000-1000-8000-00805f9b34fb';

/// Nordic UART Service (NUS) — some newer T-Scale / Kern / Adam scales.
const _nusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _nusTxCharUuid  = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // scale → phone

/// Standard GATT Weight Measurement (Bluetooth SIG 0x1808 / 0x2A98).
const _gattWeightServiceUuid = '00001808-0000-1000-8000-00805f9b34fb';
const _gattWeightCharUuid    = '00002a98-0000-1000-8000-00805f9b34fb';

/// SP110 / Crane Scale CE BLE module (0xFFB0 / 0xFFB2).
/// Common in Chinese hanging/crane scales.
const _craneServiceUuid = '0000ffb0-0000-1000-8000-00805f9b34fb';
const _craneCharUuid    = '0000ffb2-0000-1000-8000-00805f9b34fb';

// ── State / models ────────────────────────────────────────────────────────────

enum BleState { off, scanning, connecting, connected, disconnected }

class BleWeightReading {
  final double weightKg;
  final bool isStable;
  final DateTime timestamp;
  BleWeightReading(this.weightKg, this.isStable) : timestamp = DateTime.now();
}

// ── Service ───────────────────────────────────────────────────────────────────

class BleScaleService {
  static final BleScaleService _instance = BleScaleService._();
  factory BleScaleService() => _instance;
  BleScaleService._();

  BluetoothDevice?          _device;
  BluetoothCharacteristic?  _weightChar;
  StreamSubscription?       _charSub;
  StreamSubscription?       _scanSub;
  _ScaleProtocol            _protocol = _ScaleProtocol.unknown;

  final _stateCtrl      = StreamController<BleState>.broadcast();
  final _weightCtrl     = StreamController<BleWeightReading>.broadcast();
  final _deviceNameCtrl = StreamController<String>.broadcast();

  Stream<BleState>         get stateStream      => _stateCtrl.stream;
  Stream<BleWeightReading> get weightStream      => _weightCtrl.stream;
  Stream<String>           get deviceNameStream  => _deviceNameCtrl.stream;

  BleState _state = BleState.off;
  BleState get state => _state;
  String _deviceName = 'No device';
  String get deviceName => _deviceName;

  // Stability buffer
  final List<double> _buffer = [];
  static const _bufferSize       = 5;
  static const _stableThreshold  = 0.05; // kg

  // ── Scan ─────────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    _setState(BleState.scanning);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        final scale = results.firstWhere(
          (r) => _looksLikeScale(r.device.platformName),
          orElse: () => results.first,
        );
        if (results.isNotEmpty && _looksLikeScale(scale.device.platformName)) {
          FlutterBluePlus.stopScan();
          connect(scale.device);
        }
      });
    } catch (_) {
      _setState(BleState.off);
    }
  }

  bool _looksLikeScale(String name) {
    final n = name.toLowerCase();
    return n.contains('t-scale') ||
        n.contains('tscale')     ||
        n.contains('scale')      ||
        n.contains('crane')      ||
        n.contains('t7')         ||
        n.contains('a12')        ||
        n.contains('kern')       ||
        n.contains('adam')       ||
        n.contains('cas ')       ||
        n.contains('ohaus');
  }

  // ── Connect ──────────────────────────────────────────────────────────────────

  Future<void> connect(BluetoothDevice device) async {
    _setState(BleState.connecting);
    _device     = device;
    _deviceName = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.str;
    _deviceNameCtrl.add(_deviceName);

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 12));
      _setState(BleState.connected);

      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _setState(BleState.disconnected);
          _cleanup();
        }
      });

      await _discoverAndSubscribe(device);
    } catch (_) {
      _setState(BleState.disconnected);
    }
  }

  // ── Service / characteristic discovery ───────────────────────────────────────
  //
  // Priority:
  //   1. Crane / SP110  (0xFFB0 / 0xFFB2) — Crane Scale CE
  //   2. HM-10          (0xFFE0 / 0xFFE1) — T-Scale, most Chinese OEM
  //   3. NUS            (Nordic UART TX)   — newer T-Scale firmware
  //   4. GATT           (0x1808 / 0x2A98)  — Bluetooth SIG standard
  //   5. Any characteristic with Notify/Indicate property (last resort)

  /// Normalises a UUID string so we can compare regardless of whether
  /// flutter_blue_plus returns the short form ("ffe0") or the full 128-bit
  /// form ("0000ffe0-0000-1000-8000-00805f9b34fb").
  bool _uuidMatches(String actual, String expected) {
    final a = actual.toLowerCase().replaceAll('-', '');
    final e = expected.toLowerCase().replaceAll('-', '');
    if (a == e) return true;
    // Short Bluetooth SIG UUID (4 chars) — expands to 0000XXXX0000100080000000805f9b34fb
    if (a.length == 4 && e.length == 32) return e.startsWith('0000$a');
    if (e.length == 4 && a.length == 32) return a.startsWith('0000$e');
    // 8-char short form
    if (a.length == 8 && e.length == 32) return e.startsWith(a);
    if (e.length == 8 && a.length == 32) return a.startsWith(e);
    return false;
  }

  // Generic GATT characteristics that are NOT weight data — skip in last-resort
  static const _skipUuids = {
    '2a05', // Service Changed
    '2a00', // Device Name
    '2a01', // Appearance
    '2a02', // Peripheral Privacy Flag
    '2a03', // Reconnection Address
    '2a04', // Peripheral Preferred Connection Parameters
    '2902', // Client Characteristic Configuration
  };

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    debugPrint('[BLE] Services found: ${services.map((s) => s.uuid.toString()).join(', ')}');
    for (final svc in services) {
      debugPrint('[BLE]   svc=${svc.uuid}  chars=${svc.characteristics.map((c) => '${c.uuid}(N:${c.properties.notify},I:${c.properties.indicate})').join(', ')}');
    }

    BluetoothCharacteristic? found;
    _ScaleProtocol proto = _ScaleProtocol.unknown;

    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();

      if (_uuidMatches(svcUuid, _craneServiceUuid)) {
        for (final ch in svc.characteristics) {
          if (_uuidMatches(ch.uuid.toString(), _craneCharUuid)) {
            found = ch; proto = _ScaleProtocol.craneBinary; break;
          }
        }
      } else if (_uuidMatches(svcUuid, _hm10ServiceUuid)) {
        // Look for ffe1 first, then any notify char (some T-scales use ffe4)
        for (final ch in svc.characteristics) {
          if (_uuidMatches(ch.uuid.toString(), _hm10CharUuid)) {
            found = ch; proto = _ScaleProtocol.hm10Ascii; break;
          }
        }
        if (found == null) {
          for (final ch in svc.characteristics) {
            if (ch.properties.notify || ch.properties.indicate) {
              found = ch; proto = _ScaleProtocol.hm10Ascii; break;
            }
          }
        }
      } else if (_uuidMatches(svcUuid, _nusServiceUuid)) {
        for (final ch in svc.characteristics) {
          if (_uuidMatches(ch.uuid.toString(), _nusTxCharUuid)) {
            found = ch; proto = _ScaleProtocol.nusAscii; break;
          }
        }
      } else if (_uuidMatches(svcUuid, _gattWeightServiceUuid)) {
        for (final ch in svc.characteristics) {
          if (_uuidMatches(ch.uuid.toString(), _gattWeightCharUuid)) {
            found = ch; proto = _ScaleProtocol.gattBinary; break;
          }
        }
      }

      if (found != null) break;
    }

    // Last resort: first notifiable/indicatable characteristic, skipping
    // well-known non-weight GATT characteristics.
    if (found == null) {
      outer:
      for (final svc in services) {
        for (final ch in svc.characteristics) {
          final shortUuid = ch.uuid.toString().toLowerCase()
              .replaceAll(RegExp(r'^0+|-.+'), '');
          if (_skipUuids.contains(shortUuid)) continue;
          if (ch.properties.notify || ch.properties.indicate) {
            found = ch; proto = _ScaleProtocol.unknown; break outer;
          }
        }
      }
    }

    if (found == null) {
      debugPrint('[BLE] No usable characteristic found');
      return;
    }

    debugPrint('[BLE] Using char ${found.uuid} proto=$proto');

    _weightChar = found;
    _protocol   = proto;
    await found.setNotifyValue(true);
    // Use onValueReceived for all notifications (not just last value)
    _charSub = found.onValueReceived.listen(_onData);
  }

  // ── Data parsing ──────────────────────────────────────────────────────────────

  void _onData(List<int> data) {
    if (data.isEmpty) return;

    // Log raw bytes for debugging
    debugPrint('[BLE] Raw: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')} | '
        'ASCII: "${String.fromCharCodes(data.where((b) => b >= 32 && b < 127))}"');

    switch (_protocol) {
      case _ScaleProtocol.gattBinary:
        _parseGatt(data);
        break;
      case _ScaleProtocol.craneBinary:
        // Try crane binary first, fall back to ASCII
        if (!_parseCrane(data)) _parseAscii(data);
        break;
      case _ScaleProtocol.hm10Ascii:
      case _ScaleProtocol.nusAscii:
      case _ScaleProtocol.unknown:
        // Try ASCII first; if nothing parsed, try crane binary as fallback
        if (!_parseAscii(data)) _parseCrane(data);
        break;
    }
  }

  /// Crane Scale CE / SP110 binary format.
  /// Common format: [02 ST WH WL UN CS 03]
  ///   02 = STX, 03 = ETX, ST = status/stability byte,
  ///   WH/WL = weight high/low bytes (×0.1 or ×0.01 depending on model),
  ///   UN = unit (0=kg, 1=lb), CS = checksum
  /// Returns true if data was successfully parsed.
  bool _parseCrane(List<int> data) {
    // Format 1: 7-byte binary [02 ST WH WL UN CS 03]
    if (data.length >= 6 && data[0] == 0x02) {
      final stable = data[1] == 0x00 || data[1] == 0x01;
      final raw    = (data[2] << 8) | data[3];
      final unit   = data.length > 4 ? data[4] : 0;
      // Scale factor: try ×0.01 (gives kg with 2 decimal places)
      double kg = raw * 0.01;
      if (unit == 1) kg *= 0.453592; // lb → kg
      if (kg > 0 && kg < 2000) {
        _addToBuffer(kg, stable);
        return true;
      }
      // Try ×0.1 if ×0.01 gave unreasonable value
      kg = raw * 0.1;
      if (unit == 1) kg *= 0.453592;
      if (kg > 0 && kg < 2000) {
        _addToBuffer(kg, stable);
        return true;
      }
    }

    // Format 2: 6-byte [ST WH WL UN CS 03] (no STX)
    if (data.length >= 5 && data.last == 0x03) {
      final raw = (data[1] << 8) | data[2];
      double kg = raw * 0.01;
      if (kg > 0 && kg < 2000) {
        _addToBuffer(kg, false);
        return true;
      }
    }

    return false;
  }

  /// Standard GATT Weight Measurement binary.
  void _parseGatt(List<int> data) {
    if (data.length < 3) return;
    final imperial  = (data[0] & 0x01) == 1;
    final rawWeight = (data[2] << 8) | data[1];
    final kg        = imperial ? rawWeight * 0.005 * 0.453592 : rawWeight * 0.005;
    _addToBuffer(kg, false);
  }

  /// ASCII weight string: "  2.340 kg\r\n", "+  2.340 kg", "ST,GS,+0002.340kg", etc.
  /// Returns true if a value was parsed.
  bool _parseAscii(List<int> data) {
    final raw = utf8.decode(data, allowMalformed: true).trim();
    if (raw.isEmpty) return false;

    // Stability detection:
    // - Crane Scale CE: "=*Z*S  1.3kg" → 'S' at index 4 means stable/zero
    //                   "=****  1.3kg" → all * means unstable
    // - T-Scale SPP:    "ST,GS" = stable, "US,GS" = unstable
    final isStable = raw.startsWith('ST')
        || raw.startsWith('S ')
        || (raw.length >= 5 && raw[4] == 'S'); // Crane Scale CE stable flag

    final match = RegExp(r'[-+]?\d+\.?\d*').firstMatch(raw);
    if (match == null) return false;

    final value = double.tryParse(match.group(0)!);
    if (value == null || value < 0) return false;

    final lower = raw.toLowerCase();
    final isGrams = lower.contains(' g') && !lower.contains('kg');
    final kg = isGrams ? value / 1000.0 : value;

    if (kg <= 0 || kg > 2000) return false;

    _addToBuffer(kg, isStable);
    return true;
  }

  // ── Stability buffer ──────────────────────────────────────────────────────────

  void _addToBuffer(double value, bool forceStable) {
    _buffer.add(value);
    if (_buffer.length > _bufferSize) _buffer.removeAt(0);
    final stable = forceStable || _isStable();
    _weightCtrl.add(BleWeightReading(value, stable));
  }

  bool _isStable() {
    if (_buffer.length < _bufferSize) return false;
    final min = _buffer.reduce((a, b) => a < b ? a : b);
    final max = _buffer.reduce((a, b) => a > b ? a : b);
    return (max - min) <= _stableThreshold;
  }

  // ── Tare ──────────────────────────────────────────────────────────────────────

  Future<void> tare() async {
    _buffer.clear();
    if (_weightChar != null &&
        (_weightChar!.properties.write ||
         _weightChar!.properties.writeWithoutResponse)) {
      try {
        await _weightChar!.write([0x54], withoutResponse: true); // 'T'
      } catch (_) {}
    }
  }

  // ── Disconnect / cleanup ──────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _cleanup();
    await _device?.disconnect();
    _setState(BleState.off);
  }

  Future<void> _cleanup() async {
    await _charSub?.cancel();
    await _scanSub?.cancel();
    _charSub    = null;
    _scanSub    = null;
    _weightChar = null;
    _protocol   = _ScaleProtocol.unknown;
    _buffer.clear();
  }

  void _setState(BleState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _cleanup();
    _stateCtrl.close();
    _weightCtrl.close();
    _deviceNameCtrl.close();
  }
}

enum _ScaleProtocol { unknown, hm10Ascii, nusAscii, gattBinary, craneBinary }
