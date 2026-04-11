import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Classic Bluetooth (SPP) scale service.
/// Works with T-Scale A12, T7E, CS series and any scale using
/// Serial Port Profile (these appear in phone's system BT list, not BLE scan).
class ClassicScaleService {
  static final ClassicScaleService _instance = ClassicScaleService._();
  factory ClassicScaleService() => _instance;
  ClassicScaleService._();

  BluetoothConnection? _conn;
  StreamSubscription?  _dataSub;

  final _stateCtrl   = StreamController<ClassicScaleState>.broadcast();
  final _weightCtrl  = StreamController<ClassicWeightReading>.broadcast();
  final _nameCtrl    = StreamController<String>.broadcast();

  Stream<ClassicScaleState>    get stateStream  => _stateCtrl.stream;
  Stream<ClassicWeightReading> get weightStream => _weightCtrl.stream;
  Stream<String>               get nameStream   => _nameCtrl.stream;

  ClassicScaleState _state = ClassicScaleState.disconnected;
  ClassicScaleState get state => _state;
  String _deviceName = '';
  String get deviceName => _deviceName;

  // Stability buffer
  final List<double> _buf = [];
  static const _bufSize   = 5;
  static const _threshold = 0.05;

  // Partial data accumulator (data may arrive in chunks)
  final StringBuffer _incoming = StringBuffer();

  // ── Paired devices ──────────────────────────────────────────────────────────

  /// Returns all paired (bonded) Bluetooth devices — these are the ones visible
  /// in the phone's Bluetooth settings.
  Future<List<BluetoothDevice>> pairedDevices() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices;
  }

  // ── Connect ─────────────────────────────────────────────────────────────────
  /// Returns null on success, or an error message string on failure.
  /// Retries up to 3 times — Android's secure RFCOMM often fails on the first
  /// attempt for SPP devices like T-Scale; the insecure fallback succeeds on retry.
  Future<String?> connect(BluetoothDevice device) async {
    await disconnect();
    _setState(ClassicScaleState.connecting);
    _deviceName = device.name ?? device.address;
    _nameCtrl.add(_deviceName);

    String lastError = '';

    for (int attempt = 1; attempt <= 3; attempt++) {
      // Give the BT stack time to settle between attempts
      if (attempt > 1) await Future.delayed(Duration(seconds: attempt));

      try {
        _conn = await BluetoothConnection.toAddress(device.address)
            .timeout(const Duration(seconds: 15));

        _setState(ClassicScaleState.connected);

        _dataSub = _conn!.input!.listen(
          _onData,
          onDone: () {
            _setState(ClassicScaleState.disconnected);
            _cleanup();
          },
          onError: (_) {
            _setState(ClassicScaleState.disconnected);
            _cleanup();
          },
        );
        return null; // success
      } on TimeoutException {
        lastError = 'timeout';
        await _cleanup();
      } catch (e) {
        lastError = e.toString().toLowerCase();
        await _cleanup();
      }
    }

    _setState(ClassicScaleState.disconnected);

    // Friendly error messages
    if (lastError.contains('timeout')) {
      return 'Connection timed out after 3 attempts.\n\n'
          '• Make sure the scale is powered on\n'
          '• Keep the phone within 1 metre of the scale\n'
          '• Try turning the scale off and back on';
    }
    if (lastError.contains('read failed') ||
        lastError.contains('socket') ||
        lastError.contains('bt socket')) {
      return 'The scale rejected the connection (SPP port busy).\n\n'
          '• Turn the scale off, wait 5 seconds, then turn it on\n'
          '• On your phone go to Settings → Bluetooth, forget the scale, then pair again\n'
          '• Make sure no other device is connected to the scale';
    }
    if (lastError.contains('refused') || lastError.contains('econnrefused')) {
      return 'Scale refused the connection.\n\nMake sure the scale is powered on and not connected to another device.';
    }
    return 'Connection failed after 3 attempts.\n\nError: $lastError';
  }

  // ── Data parsing ─────────────────────────────────────────────────────────────
  // T-Scale SPP outputs ASCII lines: "  2.340 kg\r\n" or "2340\r\n" etc.

  void _onData(List<int> bytes) {
    _incoming.write(utf8.decode(bytes, allowMalformed: true));
    final raw = _incoming.toString();
    final lines = raw.split(RegExp(r'[\r\n]+'));
    // Keep last element (may be incomplete)
    _incoming.clear();
    if (!raw.endsWith('\n') && !raw.endsWith('\r')) {
      _incoming.write(lines.last);
      lines.removeLast();
    }
    for (final line in lines) {
      _parseLine(line.trim());
    }
  }

  void _parseLine(String line) {
    if (line.isEmpty) return;

    // Skip overload / error strings
    final lower = line.toLowerCase();
    if (lower.contains('ol') || lower.contains('err') || lower.contains('----')) return;

    // Extract first numeric value
    final match = RegExp(r'[-+]?\d+\.?\d*').firstMatch(line);
    if (match == null) return;
    final value = double.tryParse(match.group(0)!);
    if (value == null || value < 0) return;

    // Unit detection: grams if 'g' without 'kg'
    final isGrams = lower.contains(' g') && !lower.contains('kg');
    final kg = isGrams ? value / 1000.0 : value;

    _buf.add(kg);
    if (_buf.length > _bufSize) _buf.removeAt(0);

    final stable = _buf.length >= _bufSize &&
        (_buf.reduce((a, b) => a > b ? a : b) -
         _buf.reduce((a, b) => a < b ? a : b)) <= _threshold;

    _weightCtrl.add(ClassicWeightReading(kg, stable));
  }

  // ── Tare ─────────────────────────────────────────────────────────────────────

  Future<void> tare() async {
    _buf.clear();
    try {
      _conn?.output.add(ascii.encode('T\r\n'));
      await _conn?.output.allSent;
    } catch (_) {}
  }

  // ── Disconnect ───────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _cleanup();
    _setState(ClassicScaleState.disconnected);
  }

  Future<void> _cleanup() async {
    await _dataSub?.cancel();
    _dataSub = null;
    await _conn?.close();
    _conn = null;
    _buf.clear();
    _incoming.clear();
  }

  void _setState(ClassicScaleState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _cleanup();
    _stateCtrl.close();
    _weightCtrl.close();
    _nameCtrl.close();
  }
}

enum ClassicScaleState { disconnected, connecting, connected }

class ClassicWeightReading {
  final double weightKg;
  final bool isStable;
  final DateTime timestamp;
  ClassicWeightReading(this.weightKg, this.isStable) : timestamp = DateTime.now();
}
