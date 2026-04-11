import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakulima/core/ble/ble_scale_service.dart';
import 'package:wakulima/core/ble/classic_scale_service.dart';
import 'package:wakulima/core/database/farmers_local_repository.dart';
import 'package:wakulima/core/database/milk_collection_local_repository.dart';
import 'package:wakulima/core/database/models/milk_collection_model.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/sync/sync_engine.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/auth/data/auth_api_service.dart';

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});
  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _routeCtrl  = TextEditingController();
  final _manualCtrl = TextEditingController();

  bool   _useWeighDevice = true;
  double _gross = 0.0;
  double _tare  = 0.1;
  bool   _scaleConnected = false;
  bool   _submitting = false;

  // Selected IDs from dropdowns
  int?    _selectedRouteId;
  int?    _selectedShiftId;
  String? _selectedRouteName;

  // Farmers for selected route
  List<_FarmerItem> _farmers = [];
  int?    _selectedFarmerId;
  bool    _loadingFarmers = false;

  // Pending entries — accumulated before batch submit
  final List<_PendingEntry> _pendingEntries = [];

  // Classic Bluetooth scale (T-Scale, SPP)
  final _classic = ClassicScaleService();
  StreamSubscription? _weightSub;
  StreamSubscription? _bleSub;

  double get _net => _gross - _tare;

  @override
  void initState() {
    super.initState();
    _preloadFromHive(); // synchronous — farmers ready before first frame
    _upgradeFromIsarAsync(); // background upgrade from Isar
  }

  /// Synchronous — reads route + farmers from Hive instantly.
  void _preloadFromHive() {
    final box = Hive.box('auth');

    final routeRaw = box.get('route');
    if (routeRaw is Map) {
      final route = Map<String, dynamic>.from(routeRaw);
      _selectedRouteId   = (route['id'] as num?)?.toInt();
      _selectedRouteName = route['route_name'] as String?;
    }

    final farmersRaw = box.get('farmers');
    if (farmersRaw is List) {
      _farmers = farmersRaw.map((f) {
        final m = Map<String, dynamic>.from(f as Map);
        return _FarmerItem(
          id:   (m['id'] as num).toInt(),
          name: '${m['full_name']} (${m['farmer_no']})',
        );
      }).toList();
    }
  }

  /// Background: replace Hive list with Isar records (richer, with serverId).
  /// Falls back to API fetch if both Hive and Isar caches are empty.
  Future<void> _upgradeFromIsarAsync() async {
    final routeId = _selectedRouteId;
    if (routeId == null) return;
    try {
      final local = await FarmersLocalRepository().getByRoute(routeId);
      if (local.isNotEmpty && mounted) {
        setState(() {
          _farmers = local.map((f) => _FarmerItem(
            id:   f.serverId ?? 0,
            name: '${f.name} (${f.farmerCode})',
          )).toList();
        });
        return;
      }
    } catch (_) {}
    // Both Hive and Isar empty — fetch from API
    if (_farmers.isEmpty) {
      await _loadFarmersByRoute(routeId);
    }
  }

  Map<String, dynamic> get _graderUser {
    final u = Hive.box('auth').get('user');
    return u is Map ? Map<String, dynamic>.from(u) : {};
  }

  String get _storeNo    => _graderUser['loc_code'] as String? ?? '—';
  String get _locCode    => _graderUser['loc_code'] as String? ?? '—';
  String get _graderName => _graderUser['name'] as String? ?? 'Grader';
  int?   get _locationId => _graderUser['location_id'] as int?;

  String get _formattedDate {
    final now = DateTime.now();
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[now.month]} ${now.day}, ${now.year}';
  }

  String get _formattedTime {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String get _shiftLabel {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Morning Shift';
    if (h >= 12 && h < 17) return 'Afternoon Shift';
    return 'Evening Shift';
  }

  IconData get _shiftIcon {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return Icons.wb_sunny_outlined;
    if (h >= 12 && h < 17) return Icons.wb_sunny;
    return Icons.brightness_3_outlined;
  }

  Future<void> _loadFarmersByRoute(int routeId) async {
    setState(() { _farmers = []; _selectedFarmerId = null; _loadingFarmers = true; });
    final svc = AuthApiService(ApiClient());
    final raw = await svc.getFarmersByRoute(routeId);
    if (!mounted) return;
    setState(() {
      _farmers = raw.map((f) => _FarmerItem(
        id:   f['id'] as int,
        name: '${f['full_name']} (${f['farmer_no']})',
      )).toList();
      _loadingFarmers = false;
    });
  }

  Future<bool> _ensureBtPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();
      final denied = statuses.values.any(
          (s) => s.isDenied || s.isPermanentlyDenied);
      if (denied) {
        _snack('Allow Bluetooth and Location permissions and try again');
        return false;
      }
      // Classic BT discovery requires Location Services to be ON
      final locEnabled = await Permission.location.serviceStatus;
      if (!locEnabled.isEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Location Required',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 15)),
              content: const Text(
                'Android requires Location Services to be ON for Bluetooth device discovery.\n\n'
                'Please enable Location in your phone\'s quick settings, then try again.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK',
                      style: TextStyle(fontFamily: 'Poppins',
                          color: WakulimaColors.primary700)),
                ),
              ],
            ),
          );
        }
        return false;
      }
    }
    try {
      final state = await FlutterBluetoothSerial.instance.state;
      if (state != BluetoothState.STATE_ON) {
        _snack('Please turn on Bluetooth');
        return false;
      }
    } catch (_) {}
    return true;
  }

  Future<void> _showBleScanSheet() async {
    if (!await _ensureBtPermissions()) return;

    List<BluetoothDevice> paired    = [];
    // Classic BT results
    List<BluetoothDiscoveryResult> discovered = [];
    // BLE results keyed by device id
    final Map<String, fbp.ScanResult> bleResults = {};
    bool loadingPaired  = true;
    bool scanning       = false;
    StreamSubscription? discoverySub;
    StreamSubscription? bleScanSub;

    Future<void> loadPaired(StateSetter setSheet) async {
      try {
        final devices = await _classic.pairedDevices();
        setSheet(() { paired = devices; loadingPaired = false; });
      } catch (_) {
        setSheet(() => loadingPaired = false);
      }
    }

    Future<void> startDiscovery(StateSetter setSheet) async {
      setSheet(() { discovered = []; bleResults.clear(); scanning = true; });

      // Classic BT discovery
      try {
        discoverySub = FlutterBluetoothSerial.instance
            .startDiscovery()
            .listen((r) {
          setSheet(() {
            discovered.removeWhere((d) => d.device.address == r.device.address);
            discovered.add(r);
          });
        }, onDone: () {
          setSheet(() => scanning = bleResults.isNotEmpty ? scanning : false);
        });
      } catch (_) {}

      // BLE scan simultaneously
      try {
        await fbp.FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 12));
        bleScanSub = fbp.FlutterBluePlus.scanResults.listen((results) {
          setSheet(() {
            for (final r in results) {
              bleResults[r.device.remoteId.str] = r;
            }
          });
        });
        fbp.FlutterBluePlus.isScanning.listen((isScanning) {
          if (!isScanning) setSheet(() => scanning = false);
        });
      } catch (_) {
        setSheet(() => scanning = false);
      }
    }

    Future<bool> _tryBond(String address, {String? pin}) async {
      try {
        final result = await FlutterBluetoothSerial.instance
            .bondDeviceAtAddress(address, pin: pin)
            .timeout(const Duration(seconds: 20));
        return result == true;
      } catch (_) {
        return false;
      }
    }

    Future<void> pairDevice(
        BluetoothDevice device, StateSetter setSheet, BuildContext sheetCtx) async {
      discoverySub?.cancel();
      bleScanSub?.cancel();
      await fbp.FlutterBluePlus.stopScan();
      setSheet(() => scanning = false);

      final deviceName = device.name ?? device.address;

      void showProgress(String msg) {
        showDialog(
          context: sheetCtx,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(strokeWidth: 2,
                  color: WakulimaColors.primary700),
              const SizedBox(height: 16),
              Text(msg, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
            ]),
          ),
        );
      }

      Future<void> connectAfterBond() async {
        final devices = await _classic.pairedDevices();
        setSheet(() { paired = devices; });
        final match = devices.firstWhere(
            (d) => d.address == device.address,
            orElse: () => device);
        if (mounted) Navigator.pop(sheetCtx);
        _connectClassic(match);
      }

      // Step 1 — try without PIN (Android shows system dialog if needed)
      showProgress('Pairing with $deviceName…');
      bool bonded = await _tryBond(device.address);
      Navigator.of(sheetCtx, rootNavigator: true).pop();

      if (bonded) { await connectAfterBond(); return; }

      // Step 2 — try common default PINs silently
      for (final pin in ['0000', '1234', '1111', '0001']) {
        showProgress('Trying PIN $pin…');
        bonded = await _tryBond(device.address, pin: pin);
        Navigator.of(sheetCtx, rootNavigator: true).pop();
        if (bonded) { await connectAfterBond(); return; }
      }

      // Step 3 — ask user for PIN
      final pinController = TextEditingController();
      final userPin = await showDialog<String>(
        context: sheetCtx,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter PIN',
              style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Pairing with $deviceName failed with default PINs.\n'
                'Enter the PIN shown on the scale (check its manual):',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'e.g. 0000 or 1234',
                  border: OutlineInputBorder()),
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(fontFamily: 'Poppins',
                        color: WakulimaColors.inkMuted))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, pinController.text.trim()),
              child: const Text('Pair',
                  style: TextStyle(fontFamily: 'Poppins',
                      color: WakulimaColors.primary700,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (userPin != null && userPin.isNotEmpty) {
        showProgress('Pairing with PIN…');
        bonded = await _tryBond(device.address, pin: userPin);
        Navigator.of(sheetCtx, rootNavigator: true).pop();
        if (bonded) { await connectAfterBond(); return; }
      }

      _snack('Pairing failed. Make sure the scale is in pairing mode and try again.');
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (loadingPaired) {
            Future.microtask(() => loadPaired(setSheet));
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // drag handle
                Center(
                  child: Container(width: 36, height: 4,
                      decoration: BoxDecoration(
                          color: WakulimaColors.border,
                          borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 14),

                // ── Paired devices ──────────────────────────────────────
                Row(children: [
                  const Text('Paired Devices',
                      style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (loadingPaired)
                    const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 8),
                if (!loadingPaired && paired.isEmpty)
                  const Text('No paired devices found.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: WakulimaColors.inkMuted))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: paired.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: WakulimaColors.border),
                      itemBuilder: (_, i) {
                        final d = paired[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.bluetooth,
                              color: WakulimaColors.primary600),
                          title: Text(d.name ?? 'Unknown',
                              style: const TextStyle(fontFamily: 'Poppins',
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(d.address,
                              style: const TextStyle(fontFamily: 'Poppins',
                                  fontSize: 11, color: WakulimaColors.inkMuted)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _connectClassic(d);
                          },
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),
                Divider(color: WakulimaColors.border),
                const SizedBox(height: 8),

                // ── Discover nearby ────────────────────────────────────
                Row(children: [
                  const Text('Nearby Devices',
                      style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (scanning)
                    Row(children: [
                      const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: WakulimaColors.primary600)),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          discoverySub?.cancel();
                          bleScanSub?.cancel();
                          await fbp.FlutterBluePlus.stopScan();
                          setSheet(() => scanning = false);
                        },
                        child: const Text('Stop',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 12, color: WakulimaColors.error)),
                      ),
                    ])
                  else
                    TextButton.icon(
                      onPressed: () => startDiscovery(setSheet),
                      icon: const Icon(Icons.search, size: 16,
                          color: WakulimaColors.primary700),
                      label: const Text('Scan',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 12, color: WakulimaColors.primary700)),
                    ),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Tap a device to pair and connect. Make sure the scale is in pairing mode.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: WakulimaColors.inkMuted),
                ),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  // BLE takes priority — if a device appears in both BLE and
                  // Classic scan, prefer BLE (no PIN pairing needed).
                  final bleItems = bleResults.values
                      .where((r) => r.device.platformName.isNotEmpty)
                      .map((r) => _FoundDevice(
                        name: r.device.platformName,
                        address: r.device.remoteId.str,
                        rssi: r.rssi,
                        isBle: true,
                        bleDevice: r.device,
                      )).toList();

                  final bleAddresses =
                      bleItems.map((d) => d.address.toUpperCase()).toSet();

                  // Only include Classic devices NOT found via BLE
                  final classicOnly = discovered
                      .where((r) => !bleAddresses
                          .contains(r.device.address.toUpperCase()))
                      .map((r) => _FoundDevice(
                        name: r.device.name?.isNotEmpty == true
                            ? r.device.name! : 'Unknown',
                        address: r.device.address,
                        rssi: r.rssi,
                        isBle: false,
                        classicDevice: r.device,
                      )).toList();

                  // BLE first, then Classic-only devices
                  final all = [...bleItems, ...classicOnly];

                  if (all.isEmpty && !scanning) {
                    return const Text(
                      'Tap Scan to discover nearby Bluetooth scales.\n'
                      'Make sure Location is ON and the scale is powered on.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: WakulimaColors.inkMuted));
                  }

                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: all.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: WakulimaColors.border),
                      itemBuilder: (_, i) {
                        final fd = all[i];
                        final alreadyPaired = paired.any(
                            (p) => p.address.toUpperCase() ==
                                fd.address.toUpperCase());
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            fd.isBle ? Icons.bluetooth_audio : Icons.bluetooth,
                            color: fd.isBle
                                ? WakulimaColors.primary600
                                : WakulimaColors.inkMuted,
                          ),
                          title: Text(fd.name,
                              style: const TextStyle(fontFamily: 'Poppins',
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${fd.address}  •  ${fd.rssi} dBm'
                            '${fd.isBle ? '  •  BLE' : '  •  Classic'}',
                            style: const TextStyle(fontFamily: 'Poppins',
                                fontSize: 11, color: WakulimaColors.inkMuted),
                          ),
                          trailing: Text(
                            fd.isBle
                                ? 'Tap to connect'
                                : (alreadyPaired ? 'Paired' : 'Tap to pair'),
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 11,
                                color: alreadyPaired
                                    ? WakulimaColors.success
                                    : WakulimaColors.primary700)),
                          onTap: () {
                            // BLE: connect directly — no PIN needed
                            if (fd.isBle && fd.bleDevice != null) {
                              Navigator.pop(ctx);
                              _connectBle(fd.bleDevice!);
                            } else if (alreadyPaired &&
                                fd.classicDevice != null) {
                              Navigator.pop(ctx);
                              _connectClassic(fd.classicDevice!);
                            } else if (fd.classicDevice != null) {
                              pairDevice(fd.classicDevice!, setSheet, ctx);
                            }
                          },
                        );
                      },
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
    // Stop all scanning when sheet dismissed
    await discoverySub?.cancel();
    await bleScanSub?.cancel();
    await fbp.FlutterBluePlus.stopScan();
  }

  Future<void> _connectBle(fbp.BluetoothDevice device) async {
    _weightSub?.cancel();
    _bleSub?.cancel();

    final bleService = BleScaleService();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(strokeWidth: 2,
                color: WakulimaColors.primary700),
            const SizedBox(height: 16),
            Text('Connecting to ${device.platformName}…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
          ]),
        ),
      );
    }

    // Subscribe to weight stream directly — do NOT nest inside state listener
    // to avoid missing events on the broadcast stream after connect completes.
    _weightSub = bleService.weightStream.listen((r) {
      if (mounted && r.weightKg > 0) setState(() => _gross = r.weightKg);
    });
    _bleSub = bleService.stateStream.listen((s) {
      if (!mounted) return;
      if (s == BleState.connected) {
        setState(() => _scaleConnected = true);
      } else if (s == BleState.disconnected) {
        setState(() => _scaleConnected = false);
      }
    });

    await bleService.connect(device);

    // If BLE connect failed, try explicit Android bond then retry once
    if (bleService.state != BleState.connected && Platform.isAndroid) {
      try {
        await device.createBond();
        await Future.delayed(const Duration(seconds: 2));
        await bleService.connect(device);
      } catch (_) {}
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;

    if (bleService.state == BleState.connected) {
      setState(() => _scaleConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.bluetooth_connected, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('${device.platformName} connected — place load on scale',
              style: const TextStyle(fontFamily: 'Poppins')),
        ]),
        backgroundColor: WakulimaColors.success,
        duration: const Duration(seconds: 3),
      ));
    } else {
      _snack('BLE connection failed — power cycle the scale and try again');
    }
  }

  Future<void> _connectClassic(BluetoothDevice device) async {
    _bleSub?.cancel();
    _weightSub?.cancel();

    // Subscribe to state before connecting
    _bleSub = _classic.stateStream.listen((s) {
      if (!mounted) return;
      if (s == ClassicScaleState.connected) {
        setState(() => _scaleConnected = true);
        _weightSub = _classic.weightStream.listen((r) {
          if (mounted) setState(() => _gross = r.weightKg);
        });
      } else if (s == ClassicScaleState.disconnected) {
        if (mounted) setState(() => _scaleConnected = false);
      }
    });

    // Show connecting dialog
    final name = device.name ?? device.address;
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(strokeWidth: 2,
                color: WakulimaColors.primary700),
            const SizedBox(height: 16),
            Text('Connecting to $name…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            const SizedBox(height: 6),
            const Text('May take up to 30 seconds on first connect',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: WakulimaColors.inkMuted)),
          ]),
        ),
      );
    }

    final error = await _classic.connect(device);

    // Close dialog
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;

    if (error == null) {
      // Success
      setState(() => _scaleConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.bluetooth_connected, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('$name connected — weight will auto-fill',
              style: const TextStyle(fontFamily: 'Poppins')),
        ]),
        backgroundColor: WakulimaColors.success,
        duration: const Duration(seconds: 3),
      ));
    } else {
      // Failure — show dialog with specific reason
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.bluetooth_disabled, color: WakulimaColors.error),
            const SizedBox(width: 8),
            const Text('Connection Failed',
                style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          content: Text(error,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK',
                  style: TextStyle(fontFamily: 'Poppins',
                      color: WakulimaColors.primary700,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _connectClassic(device);
              },
              child: const Text('Retry',
                  style: TextStyle(fontFamily: 'Poppins',
                      color: WakulimaColors.primary700,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
  }

  // ── Offline-first submit ────────────────────────────────────────────────────
  //
  // Priority:
  //   1. Online  → POST directly; on success reset form.
  //   2. Network error while online  → fallback: save to Isar queue.
  //   3. Offline  → save to Isar queue immediately.
  //
  // Isar records are picked up by SyncEngine which auto-syncs on reconnect
  // and every 5 minutes while online.
  // ────────────────────────────────────────────────────────────────────────────

  // ── Add current reading to the pending list ──────────────────────────────────

  void _addEntry() {
    if (_selectedRouteId  == null) { _snack('Select a route');   return; }
    if (_selectedShiftId  == null) { _snack('Select a shift');   return; }
    if (_selectedFarmerId == null) { _snack('Select a farmer');  return; }
    if (_net <= 0) { _snack('Net weight must be greater than 0'); return; }

    final farmer    = _farmers.firstWhere(
        (f) => f.id == _selectedFarmerId,
        orElse: () => _FarmerItem(id: _selectedFarmerId!, name: 'Farmer $_selectedFarmerId'));
    final nameMatch = RegExp(r'^(.*?)\s*\(([^)]+)\)$').firstMatch(farmer.name);
    final farmerName = nameMatch?.group(1)?.trim() ?? farmer.name;
    final farmerCode = nameMatch?.group(2) ?? '$_selectedFarmerId';

    setState(() {
      _pendingEntries.add(_PendingEntry(
        farmerId:   _selectedFarmerId!,
        farmerName: farmerName,
        farmerCode: farmerCode,
        weightKg:   _net,
      ));
      // Clear weight + farmer, keep route + shift for next entry
      _gross = 0.0;
      _selectedFarmerId = null;
      _manualCtrl.clear();
    });
  }

  // ── Submit all pending entries ────────────────────────────────────────────────

  Future<void> _submitAll() async {
    if (_pendingEntries.isEmpty) { _snack('Add at least one entry first'); return; }

    setState(() => _submitting = true);
    final now = DateTime.now();

    try {
      if (SyncEngine().isOnline) {
        try {
          await _submitAllOnline(now);
          return;
        } on DioException catch (e) {
          if (e.response != null) {
            final body = e.response?.data;
            final msg  = (body is Map ? body['message'] : null)
                as String? ?? 'Submission failed';
            _snack(msg);
            return;
          }
        }
      }
      await _saveAllOffline(now);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitAllOnline(DateTime now) async {
    final api     = ref.read(apiClientProvider);
    final dateStr = _isoDate(now);

    final payload = <String, dynamic>{
      'route_id':     _selectedRouteId,
      'shift_id':     _selectedShiftId,
      'invoice_date': dateStr,
      'pricing_type': 'normal',
      'items': _pendingEntries.map((e) => {
        'farmer_id': e.farmerId,
        'quantity':  double.parse(e.weightKg.toStringAsFixed(3)),
      }).toList(),
    };
    if (_locationId != null) payload['grader_id'] = _locationId;

    final res  = await api.post('/farmers/milk-purchases', data: payload);
    if (!mounted) return;

    final body = res.data as Map<String, dynamic>;
    final msg  = body['message'] as String? ?? 'Recorded successfully';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ $msg'),
      backgroundColor: WakulimaColors.success,
      duration: const Duration(seconds: 4),
    ));
    _resetAll();
  }

  Future<void> _saveAllOffline(DateTime now) async {
    for (int i = 0; i < _pendingEntries.length; i++) {
      final e = _pendingEntries[i];
      final ts = now.add(Duration(milliseconds: i)); // unique timestamps
      final model = MilkCollectionModel()
        ..uuid             = 'offline-${ts.millisecondsSinceEpoch}-${e.farmerId}'
        ..farmerName       = e.farmerName
        ..farmerServerId   = e.farmerId
        ..routeId          = _selectedRouteId
        ..shiftId          = _selectedShiftId
        ..graderLocationId = _locationId ?? 0
        ..farmerId         = e.farmerCode
        ..weightKg         = e.weightKg
        ..pricePerKg       = 0.0
        ..totalValue       = 0.0
        ..grade            = 'A'
        ..notes            = 'Offline entry'
        ..collectedAt      = ts
        ..collectedBy      = _graderName
        ..stationName      = _locCode
        ..scaleDevice      = _useWeighDevice ? 'ble' : 'manual'
        ..isStableReading  = !_useWeighDevice
        ..synced           = false;
      await MilkCollectionLocalRepository().save(model);
    }
    await SyncEngine().refreshPendingCount();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: const [
        Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 18),
        SizedBox(width: 10),
        Expanded(child: Text('Saved offline — will sync when online',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
      ]),
      backgroundColor: const Color(0xFF2563EB),
      duration: const Duration(seconds: 4),
    ));
    _resetAll();
  }

  static String _isoDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  void _resetAll() {
    _manualCtrl.clear();
    setState(() {
      _gross = 0.0;
      // Do NOT reset _scaleConnected — BLE/Classic connection persists
      // until the user disconnects or the device goes idle.
      _selectedFarmerId = null;
      _pendingEntries.clear();
    });
  }

  void _snack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? WakulimaColors.error : WakulimaColors.success,
    ));
  }

  @override
  void dispose() {
    _routeCtrl.dispose();
    _manualCtrl.dispose();
    _weightSub?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formDataAsync = ref.watch(collectionFormDataProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: formDataAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:   (e, _) => _buildBody(routes: [], shifts: []),
                data:    (data) {
                  final routes = (data['routes'] as List? ?? [])
                      .map((r) => _RouteItem(
                            id: r['id'] as int,
                            name: r['route_name'] as String,
                          ))
                      .toList();
                  final shifts = (data['shifts'] as List? ?? [])
                      .map((s) => _ShiftItem(
                            id: s['id'] as int,
                            name: s['description'] as String,
                          ))
                      .toList();

                  if (_selectedShiftId == null && shifts.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _selectedShiftId = shifts.first.id;
                        });
                      }
                    });
                  }

                  return _buildBody(routes: routes, shifts: shifts);
                },
              ),
            ),
            _buildSubmitBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required List<_RouteItem> routes,
    required List<_ShiftItem> shifts,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildShiftBanner(shifts),
          const SizedBox(height: 12),
          _buildCollectionInfo(routes),
          const SizedBox(height: 12),
          _buildWeightCollection(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 22, color: WakulimaColors.ink),
              onPressed: () => context.go('/dashboard'),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_formattedDate,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 17,
                      fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
              Text(_formattedTime,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      color: WakulimaColors.inkMuted)),
            ]),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(children: [
              Text('$_locCode  ',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: WakulimaColors.primary50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                          color: WakulimaColors.primary700, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  const Text('ONLINE',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: WakulimaColors.primary700)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Shift Banner ─────────────────────────────────────────────────────────────

  Widget _buildShiftBanner(List<_ShiftItem> shifts) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Row(children: [
        Icon(_shiftIcon, size: 18, color: WakulimaColors.gold500),
        const SizedBox(width: 8),
        Flexible(
          child: shifts.isNotEmpty
              ? _SearchableDropdown<int>(
                  value: _selectedShiftId,
                  hint: _shiftLabel,
                  items: shifts.map((s) =>
                      _DropdownEntry(value: s.id, label: s.name)).toList(),
                  onChanged: (v) => setState(() => _selectedShiftId = v),
                )
              : Text(_shiftLabel,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
        ),
        const SizedBox(width: 8),
        Text('Store: ',
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                color: WakulimaColors.inkMuted)),
        Text(_storeNo,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
      ]),
    );
  }

  // ── Collection Information ────────────────────────────────────────────────────

  Widget _buildCollectionInfo(List<_RouteItem> routes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Collection Information',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: WakulimaColors.inkMuted)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WakulimaColors.border),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  Flexible(
                    child: Text('$_graderName · $_locCode',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            color: WakulimaColors.inkMuted)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => ref.refresh(collectionFormDataProvider),
                    child: const Text('Refresh',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: WakulimaColors.primary600)),
                  ),
                ]),
              ),
              Divider(height: 1, color: WakulimaColors.border),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        text: 'Route',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w500, color: WakulimaColors.ink),
                        children: [
                          TextSpan(text: '*',
                              style: TextStyle(color: WakulimaColors.primary600))
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // If route was pre-loaded from login (grader's assigned route),
                    // show it as a locked read-only chip — graders cannot change routes.
                    if (_selectedRouteName != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: WakulimaColors.primary50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: WakulimaColors.primary200),
                        ),
                        child: Row(children: [
                          const Icon(Icons.route_outlined,
                              size: 16,
                              color: WakulimaColors.primary700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_selectedRouteName!,
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: WakulimaColors.primary700)),
                          ),
                          const Icon(Icons.lock_outline,
                              size: 14,
                              color: WakulimaColors.primary400),
                        ]),
                      )
                    else if (routes.isNotEmpty)
                      _SearchableDropdown<int>(
                        value: _selectedRouteId,
                        hint: 'Search route…',
                        items: routes.map((r) =>
                            _DropdownEntry(value: r.id, label: r.name)).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedRouteId = v;
                            _selectedRouteName =
                                routes.firstWhere((r) => r.id == v).name;
                          });
                          if (v != null) _loadFarmersByRoute(v);
                        },
                      )
                    else
                      _SearchableDropdown<int>(
                        hint: 'No route assigned',
                        items: const [],
                        onChanged: null,
                      ),
                  ],
                ),
              ),

              Divider(height: 1, color: WakulimaColors.border),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        text: 'Farmer',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w500, color: WakulimaColors.ink),
                        children: [
                          TextSpan(text: '*',
                              style: TextStyle(color: WakulimaColors.primary600))
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_loadingFarmers)
                      const SizedBox(
                        height: 42,
                        child: Center(child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else
                      _SearchableDropdown<int>(
                        value: _selectedFarmerId,
                        hint: _farmers.isEmpty
                            ? 'No farmers on this route'
                            : 'Search farmer…',
                        items: _farmers.map((f) =>
                            _DropdownEntry(value: f.id, label: f.name)).toList(),
                        onChanged: _farmers.isEmpty
                            ? null
                            : (v) => setState(() => _selectedFarmerId = v),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pinkTextField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.inkMuted),
        filled: true,
        fillColor: WakulimaColors.cream,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: WakulimaColors.border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: WakulimaColors.border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: WakulimaColors.primary700, width: 1.5),
        ),
      ),
    );
  }

  // ── Weight Collection ────────────────────────────────────────────────────────

  Widget _buildWeightCollection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weight Collection',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: WakulimaColors.inkMuted)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WakulimaColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: _WeightModeBtn(
                      label: 'Weigh Device',
                      selected: _useWeighDevice,
                      onTap: () => setState(() => _useWeighDevice = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WeightModeBtn(
                      label: 'Manual Input',
                      selected: !_useWeighDevice,
                      onTap: () => setState(() => _useWeighDevice = false),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_useWeighDevice) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Weight reading
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: '${_gross.toStringAsFixed(2)} KG ',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: WakulimaColors.ink),
                                ),
                                const TextSpan(
                                  text: 'Gross',
                                  style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12,
                                      color: WakulimaColors.inkMuted),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tare: ${_tare.toStringAsFixed(2)} KG   Net: ${_net.toStringAsFixed(2)} KG',
                              style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _net < 0
                                      ? WakulimaColors.error
                                      : WakulimaColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Connect Scale button — right-aligned
                      GestureDetector(
                        onTap: _showBleScanSheet,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _scaleConnected
                                ? WakulimaColors.success.withOpacity(0.12)
                                : WakulimaColors.primary600,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _scaleConnected
                                  ? WakulimaColors.success
                                  : WakulimaColors.primary700,
                              width: 1.2,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              _scaleConnected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth,
                              size: 16,
                              color: _scaleConnected
                                  ? WakulimaColors.success
                                  : Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _scaleConnected ? 'Connected' : 'Connect Scale',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _scaleConnected
                                      ? WakulimaColors.success
                                      : Colors.white),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  TextField(
                    controller: _manualCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    onChanged: (v) =>
                        setState(() => _gross = double.tryParse(v) ?? 0.0),
                    decoration: InputDecoration(
                      labelText: 'Weight (KG)',
                      suffixText: 'KG',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit Bar ────────────────────────────────────────────────────────────────

  Widget _buildSubmitBar() {
    final netStr  = _net.toStringAsFixed(1);
    final online  = SyncEngine().isOnline;
    final totalKg = _pendingEntries.fold(0.0, (s, e) => s + e.weightKg);

    return StreamBuilder<int>(
      stream: SyncEngine().pendingCountStream,
      initialData: SyncEngine().pendingCount,
      builder: (_, snap) {
        final pending = snap.data ?? 0;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          // Pending entries list
          if (_pendingEntries.isNotEmpty)
            Container(
              color: WakulimaColors.primary900,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.list_alt, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text('${_pendingEntries.length} entr${_pendingEntries.length == 1 ? 'y' : 'ies'} — '
                      '${totalKg.toStringAsFixed(1)} KG total',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          color: Colors.white70, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _pendingEntries.length,
                    itemBuilder: (_, i) {
                      final e = _pendingEntries[i];
                      return Row(children: [
                        Expanded(
                          child: Text(
                            '${i + 1}. ${e.farmerName}  •  ${e.weightKg.toStringAsFixed(2)} KG',
                            style: const TextStyle(fontFamily: 'Poppins',
                                fontSize: 11, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _pendingEntries.removeAt(i)),
                          child: const Icon(Icons.close, color: Colors.white54, size: 16),
                        ),
                      ]);
                    },
                  ),
                ),
              ]),
            ),
          // Offline queue badge
          if (pending > 0)
            Container(
              width: double.infinity,
              color: const Color(0xFF1D4ED8),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text('$pending record${pending == 1 ? '' : 's'} queued — waiting for connection',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          color: Colors.white)),
                ],
              ),
            ),
          // Buttons row: Add Entry | Submit All
          Row(children: [
            // Add Entry button
            Expanded(
              child: GestureDetector(
                onTap: _submitting ? null : _addEntry,
                child: SizedBox(
                  height: 52,
                  child: ColoredBox(
                    color: WakulimaColors.primary600,
                    child: Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text('Add $netStr KG',
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 14,
                                fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            // Submit All button
            if (_pendingEntries.isNotEmpty)
              Expanded(
                child: GestureDetector(
                  onTap: _submitting ? null : _submitAll,
                  child: SizedBox(
                    height: 52,
                    child: ColoredBox(
                      color: online ? WakulimaColors.primary700 : const Color(0xFF2563EB),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                                  color: Colors.white, size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  online
                                      ? 'Submit ${_pendingEntries.length}'
                                      : 'Save ${_pendingEntries.length}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white, letterSpacing: 0.3),
                                ),
                              ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      },
    );
  }
}

// ── Weight Mode Button ────────────────────────────────────────────────────────

class _WeightModeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _WeightModeBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        width: double.infinity,
        decoration: BoxDecoration(
          color: selected ? WakulimaColors.primary50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? WakulimaColors.primary700 : WakulimaColors.border,
            width: 1.3,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? WakulimaColors.primary700
                    : WakulimaColors.inkSoft)),
      ),
    );
  }
}

// ── Data helpers ──────────────────────────────────────────────────────────────

class _RouteItem {
  final int id;
  final String name;
  const _RouteItem({required this.id, required this.name});
}

class _ShiftItem {
  final int id;
  final String name;
  const _ShiftItem({required this.id, required this.name});
}

class _FarmerItem {
  final int id;
  final String name;
  const _FarmerItem({required this.id, required this.name});
}

class _PendingEntry {
  final int farmerId;
  final String farmerName;
  final String farmerCode;
  final double weightKg;
  const _PendingEntry({
    required this.farmerId,
    required this.farmerName,
    required this.farmerCode,
    required this.weightKg,
  });
}

class _FoundDevice {
  final String name;
  final String address;
  final int rssi;
  final bool isBle;
  final BluetoothDevice? classicDevice;
  final fbp.BluetoothDevice? bleDevice;

  const _FoundDevice({
    required this.name,
    required this.address,
    required this.rssi,
    required this.isBle,
    this.classicDevice,
    this.bleDevice,
  });
}

// ── Searchable Dropdown ───────────────────────────────────────────────────────

class _DropdownEntry<T> {
  final T value;
  final String label;
  const _DropdownEntry({required this.value, required this.label});
}

class _SearchableDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<_DropdownEntry<T>> items;
  final ValueChanged<T?>? onChanged;

  const _SearchableDropdown({
    required this.hint,
    required this.items,
    this.value,
    this.onChanged,
  });

  String get _selectedLabel =>
      items.firstWhere((e) => e.value == value,
          orElse: () => _DropdownEntry(value: value as T, label: hint)).label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => _openSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: onChanged == null ? WakulimaColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: WakulimaColors.border, width: 1.2),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              value != null ? _selectedLabel : hint,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: value != null
                      ? WakulimaColors.ink
                      : WakulimaColors.inkMuted),
            ),
          ),
          Icon(Icons.arrow_drop_down,
              color: onChanged == null
                  ? WakulimaColors.inkMuted
                  : WakulimaColors.inkSoft),
        ]),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _SearchableSheetContent<T>(
        items: items,
        selectedValue: value,
        onSelected: (v) => onChanged?.call(v),
      ),
    );
  }
}

class _SearchableSheetContent<T> extends StatefulWidget {
  final List<_DropdownEntry<T>> items;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  const _SearchableSheetContent({
    required this.items,
    required this.selectedValue,
    required this.onSelected,
  });
  @override
  State<_SearchableSheetContent<T>> createState() =>
      _SearchableSheetContentState<T>();
}

class _SearchableSheetContentState<T>
    extends State<_SearchableSheetContent<T>> {
  late final TextEditingController _ctrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((e) => e.label.toLowerCase().contains(_query))
            .toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: WakulimaColors.border,
                    borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13,
                    color: WakulimaColors.inkMuted),
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No results',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 13, color: WakulimaColors.inkMuted))),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: WakulimaColors.border),
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final selected = e.value == widget.selectedValue;
                      return ListTile(
                        dense: true,
                        title: Text(e.label,
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: selected
                                    ? const Color(0xFFD32F2F)
                                    : WakulimaColors.ink)),
                        trailing: selected
                            ? const Icon(Icons.check,
                                color: Color(0xFFD32F2F), size: 18)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(e.value);
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
