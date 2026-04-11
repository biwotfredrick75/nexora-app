import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/database/farmers_local_repository.dart';
import 'package:wakulima/core/database/milk_collection_local_repository.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/sync/sync_engine.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/core/widgets/sync_status_bar.dart';

// ── Provider: fetch milk purchases from backend ─────────────────────────────

final _dairyFilterProvider =
    StateProvider<_DairyFilter>((_) => _DairyFilter());

final _dairyCollectionsProvider =
    FutureProvider.autoDispose.family<_DairyResult, _DairyFilter>(
  (ref, filter) async {
    final api = ref.watch(apiClientProvider);
    final params = <String, dynamic>{
      'from':  filter.from,
      'to':    filter.to,
      'limit': '200',
    };
    if (filter.routeId != null) params['route_id'] = filter.routeId.toString();
    if (filter.shiftId != null) params['shift_id'] = filter.shiftId.toString();
    if (filter.farmerId != null) params['farmer_id'] = filter.farmerId.toString();

    try {
      final res  = await api.get('/farmers/milk-purchases', params: params);
      final body = res.data as Map<String, dynamic>;
      if (body['success'] != true) return _DairyResult.empty();

      final purchases = (body['data'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      final entries = <_CollectionEntry>[];
      for (final p in purchases) {
        final items  = (p['items'] as List? ?? []);
        final shift  = (p['shift'] as Map?)?['description'] as String? ?? '—';
        final date   = p['invoice_date'] as String? ?? '';
        for (final it in items) {
          final m = Map<String, dynamic>.from(it as Map);
          final farmer = m['farmer'] as Map?;
          entries.add(_CollectionEntry(
            farmerNo:   farmer?['farmer_no'] as String? ?? m['farmer_no'] as String? ?? '',
            farmerName: farmer?['full_name'] as String? ?? m['farmer_name'] as String? ?? m['full_name'] as String? ?? '—',
            qty:        (m['quantity'] as num?)?.toDouble() ?? 0,
            shift:      shift,
            date:       date,
            createdAt:  p['created_at'] as String? ?? date,
            purchaseId: p['id'] as int? ?? 0,
          ));
        }
      }

      // Mark duplicates: same farmer appearing more than once in the same batch
      final seen = <String>{};
      final markedEntries = entries.map((e) {
        final key    = '${e.purchaseId}_${e.farmerNo}';
        final isDup  = seen.contains(key);
        seen.add(key);
        return _CollectionEntry(
          farmerNo:    e.farmerNo,
          farmerName:  e.farmerName,
          qty:         e.qty,
          shift:       e.shift,
          date:        e.date,
          createdAt:   e.createdAt,
          purchaseId:  e.purchaseId,
          isDuplicate: isDup,
        );
      }).toList();

      final totalKg = markedEntries.fold(0.0, (s, e) => s + e.qty);
      return _DairyResult(entries: markedEntries, totalKg: totalKg);
    } catch (_) {
      return _DairyResult.empty();
    }
  },
);

// ── Models ───────────────────────────────────────────────────────────────────

class _DairyFilter {
  final String from;
  final String to;
  final int?   routeId;
  final int?   shiftId;
  final int?   farmerId;

  _DairyFilter({
    String? from,
    String? to,
    this.routeId,
    this.shiftId,
    this.farmerId,
  })  : from = from ?? _today(),
        to   = to   ?? _today();

  _DairyFilter copyWith({
    String? from, String? to, int? routeId,
    int? shiftId, Object? farmerId = _sentinel,
  }) =>
      _DairyFilter(
        from:     from     ?? this.from,
        to:       to       ?? this.to,
        routeId:  routeId  ?? this.routeId,
        shiftId:  shiftId  ?? this.shiftId,
        farmerId: farmerId == _sentinel
            ? this.farmerId
            : farmerId as int?,
      );

  static const _sentinel = Object();
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object o) =>
      o is _DairyFilter &&
      o.from == from && o.to == to &&
      o.routeId == routeId && o.shiftId == shiftId &&
      o.farmerId == farmerId;

  @override
  int get hashCode =>
      Object.hash(from, to, routeId, shiftId, farmerId);
}

class _DairyResult {
  final List<_CollectionEntry> entries;
  final double totalKg;
  _DairyResult({required this.entries, required this.totalKg});
  factory _DairyResult.empty() => _DairyResult(entries: [], totalKg: 0);
}

class _CollectionEntry {
  final String farmerNo;
  final String farmerName;
  final double qty;
  final String shift;
  final String date;
  final String createdAt;
  final int    purchaseId;
  final bool   isDuplicate;
  const _CollectionEntry({
    required this.farmerNo, required this.farmerName,
    required this.qty, required this.shift,
    required this.date, required this.createdAt,
    required this.purchaseId,
    this.isDuplicate = false,
  });
}

class _HiveFarmer {
  final int    id;
  final String farmerNo;
  final String name;
  const _HiveFarmer({required this.id, required this.farmerNo, required this.name});
}

// ── Screen ───────────────────────────────────────────────────────────────────

class DairyScreen extends ConsumerStatefulWidget {
  const DairyScreen({super.key});
  @override
  ConsumerState<DairyScreen> createState() => _DairyScreenState();
}

class _DairyScreenState extends ConsumerState<DairyScreen> {
  String _datePreset = 'Today';

  // Hive-loaded data
  int?    _routeId;
  String? _routeName;
  List<_HiveFarmer> _farmers = [];

  // Selected farmer filter
  int?    _selectedFarmerId;
  String? _selectedFarmerName;

  // Shift filter: 0=All, 1=Morning, 2=Evening
  int _shift = 0;
  // Shift IDs from form-data (loaded from API)
  List<Map<String, dynamic>> _shifts = [];

  // Search & pagination
  String _searchQuery = '';
  int _page = 0;
  static const _pageSize = 20;

  // Seeding state
  bool   _isSeeding    = false;
  double _seedFraction = 0.0;
  int    _seedCount    = 0;

  // Sync progress state (driven by SyncEngine streams)
  SyncStatus    _syncStatus   = SyncStatus.idle;
  SyncProgress? _syncProgress;
  StreamSubscription<SyncStatus>?   _syncStatusSub;
  StreamSubscription<SyncProgress>? _syncProgressSub;

  @override
  void initState() {
    super.initState();
    _loadEverythingFromHive(); // synchronous — farmers available before first frame
    _upgradeFromIsarAsync();  // async — upgrades from Isar in background
    _syncStatus = SyncEngine().status;
    _syncStatusSub = SyncEngine().statusStream.listen((s) {
      if (mounted) setState(() => _syncStatus = s);
    });
    _syncProgressSub = SyncEngine().progressStream.listen((p) {
      if (mounted) setState(() => _syncProgress = p);
    });
  }

  @override
  void dispose() {
    _syncStatusSub?.cancel();
    _syncProgressSub?.cancel();
    super.dispose();
  }

  /// Synchronous Hive load — runs before the first frame so _farmers is always
  /// populated when the farmer picker opens.
  void _loadEverythingFromHive() {
    final box = Hive.box('auth');

    // Route
    final routeRaw = box.get('route');
    if (routeRaw != null) {
      try {
        final r = Map<String, dynamic>.from(routeRaw as Map);
        _routeId   = (r['id'] as num?)?.toInt();
        _routeName = r['route_name'] as String?;
      } catch (_) {}
    }

    // Farmers from Hive (stored at login)
    final farmersRaw = box.get('farmers');
    if (farmersRaw is List) {
      for (final f in farmersRaw) {
        try {
          final m = Map<String, dynamic>.from(f as Map);
          _farmers.add(_HiveFarmer(
            id:       (m['id'] as num).toInt(),
            farmerNo: (m['farmer_no'] ?? '').toString(),
            name:     (m['full_name'] ?? m['name'] ?? '').toString(),
          ));
        } catch (_) {}
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeId != null && mounted) {
        ref.read(_dairyFilterProvider.notifier).state =
            ref.read(_dairyFilterProvider).copyWith(routeId: _routeId);
      }
    });
  }

  /// Background Isar upgrade — replaces the Hive list with the richer Isar
  /// records (which have serverId), and falls back to the API if both are empty.
  Future<void> _upgradeFromIsarAsync() async {
    if (_routeId == null) return;
    try {
      final local = await FarmersLocalRepository().getByRoute(_routeId!);
      if (local.isNotEmpty && mounted) {
        setState(() {
          _farmers = local.map((f) => _HiveFarmer(
            id:       f.serverId ?? 0,
            farmerNo: f.farmerCode,
            name:     f.name,
          )).toList();
        });
        return;
      }
    } catch (_) {}

    // Isar empty — save Hive list into Isar for next time, then try API
    final box = Hive.box('auth');
    final farmersRaw = box.get('farmers');
    if (farmersRaw is List && farmersRaw.isNotEmpty) {
      FarmersLocalRepository().saveFromLogin(farmersRaw, _routeId!);
      return; // Hive data already loaded synchronously above
    }

    if (_farmers.isEmpty) {
      _fetchFarmersFromApi(_routeId!);
    }
  }

  Future<void> _fetchFarmersFromApi(int routeId) async {
    try {
      final api = ref.read(apiClientProvider);
      final res  = await api.get('/farmers/routes/$routeId/farmers');
      final body = res.data as Map<String, dynamic>;
      if (body['success'] == true) {
        final list = (body['data']?['farmers'] as List? ?? []);
        if (!mounted) return;
        setState(() {
          _farmers = list.map((f) {
            final m = Map<String, dynamic>.from(f as Map);
            return _HiveFarmer(
              id:       (m['id'] as num).toInt(),
              farmerNo: (m['farmer_no'] ?? '').toString(),
              name:     (m['full_name'] ?? '').toString(),
            );
          }).toList();
        });
        // Cache to Isar for future offline use
        FarmersLocalRepository().saveFromLogin(list, routeId);
      }
    } catch (_) {}
  }

  /// Seed dummy offline collections (5 000 records) with progress feedback.
  Future<void> _seedDummyCollections() async {
    if (_routeId == null || _isSeeding) return;

    setState(() { _isSeeding = true; _seedFraction = 0.0; _seedCount = 0; });

    final box     = Hive.box('auth');
    final user    = box.get('user') as Map?;
    final shiftId = ref.read(_dairyFilterProvider).shiftId ?? 1;

    final result = await MilkCollectionLocalRepository().seedDummyCollections(
      routeId:           _routeId!,
      shiftId:           shiftId,
      graderLocationId:  (user?['location_id'] as num?)?.toInt() ?? 0,
      farmers: _farmers.map((f) => {
        'name':      f.name,
        'farmerCode': f.farmerNo,
        'serverId':  f.id,
      }).toList(),
      onProgress: (fraction, written) {
        if (mounted) setState(() { _seedFraction = fraction; _seedCount = written; });
      },
    );

    await SyncEngine().refreshPendingCount();

    if (mounted) {
      setState(() { _isSeeding = false; _seedFraction = 0.0; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: result.blocked ? WakulimaColors.error : null,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String get _formattedDateTime {
    final now = DateTime.now();
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    return '${months[now.month]} ${now.day}, ${now.year}  $h:$m $ampm';
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String p(int n) => n.toString().padLeft(2, '0');
      return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}:${p(dt.second)}';
    } catch (_) {
      return iso;
    }
  }

  void _updateFilter(_DairyFilter f) =>
      ref.read(_dairyFilterProvider.notifier).state = f;

  void _applyPreset(String preset) {
    final now = DateTime.now();
    DateTime from, to;
    if (preset == 'Yesterday') {
      from = to = now.subtract(const Duration(days: 1));
    } else if (preset == 'This Week') {
      from = now.subtract(Duration(days: now.weekday - 1));
      to   = now;
    } else if (preset == 'This Month') {
      from = DateTime(now.year, now.month, 1);
      to   = now;
    } else {
      from = to = now;
    }
    setState(() => _datePreset = preset);
    _updateFilter(ref.read(_dairyFilterProvider)
        .copyWith(from: _fmt(from), to: _fmt(to)));
  }

  Future<void> _pickDate(bool isFrom) async {
    final filter = ref.read(_dairyFilterProvider);
    final initial = DateTime.tryParse(isFrom ? filter.from : filter.to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: WakulimaColors.primary700),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _datePreset = 'Custom');
      _updateFilter(isFrom
          ? ref.read(_dairyFilterProvider).copyWith(from: _fmt(picked))
          : ref.read(_dairyFilterProvider).copyWith(to: _fmt(picked)));
    }
  }

  void _applyShift(int idx, List<Map<String, dynamic>> shiftItems) {
    setState(() => _shift = idx);
    final shiftId = idx == 0 ? null : (shiftItems.isNotEmpty && idx - 1 < shiftItems.length
        ? shiftItems[idx - 1]['id'] as int?
        : null);
    _updateFilter(ref.read(_dairyFilterProvider).copyWith(shiftId: shiftId));
  }

  void _showFarmerPicker() {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = query.isEmpty
              ? _farmers
              : _farmers.where((f) =>
                  f.name.toLowerCase().contains(query.toLowerCase()) ||
                  f.farmerNo.toLowerCase().contains(query.toLowerCase())).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (_, controller) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                // Handle
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: WakulimaColors.border,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Select Farmer',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                          fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
                  const Spacer(),
                  if (_selectedFarmerId != null)
                    TextButton(
                      onPressed: () {
                        setState(() { _selectedFarmerId = null; _selectedFarmerName = null; });
                        _updateFilter(ref.read(_dairyFilterProvider)
                            .copyWith(farmerId: null));
                        Navigator.pop(ctx);
                      },
                      child: const Text('Clear', style: TextStyle(
                          fontFamily: 'Poppins', color: WakulimaColors.error)),
                    ),
                ]),
                const SizedBox(height: 10),
                // Search box
                TextField(
                  autofocus: true,
                  onChanged: (v) => setSheet(() => query = v),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search name or farmer no…',
                    hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        color: WakulimaColors.inkMuted),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: WakulimaColors.cream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: WakulimaColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: WakulimaColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: WakulimaColors.primary700, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _farmers.isEmpty
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircularProgressIndicator(strokeWidth: 2,
                                color: WakulimaColors.primary700),
                            SizedBox(height: 12),
                            Text('Loading farmers…',
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontSize: 13, color: WakulimaColors.inkMuted)),
                          ])))
                      : filtered.isEmpty
                      ? const Center(child: Text('No farmers found',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 13, color: WakulimaColors.inkMuted)))
                      : ListView.separated(
                          controller: controller,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: WakulimaColors.border),
                          itemBuilder: (_, i) {
                            final f = filtered[i];
                            final selected = f.id == _selectedFarmerId;
                            return ListTile(
                              dense: true,
                              title: Text(f.name,
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                      color: selected ? WakulimaColors.primary700 : WakulimaColors.ink)),
                              subtitle: Text(f.farmerNo,
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                      color: WakulimaColors.inkMuted)),
                              trailing: selected
                                  ? const Icon(Icons.check_circle,
                                      color: WakulimaColors.primary700, size: 18)
                                  : null,
                              onTap: () {
                                setState(() {
                                  _selectedFarmerId   = f.id;
                                  _selectedFarmerName = '${f.name} (${f.farmerNo})';
                                });
                                _updateFilter(ref.read(_dairyFilterProvider)
                                    .copyWith(farmerId: f.id));
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filter    = ref.watch(_dairyFilterProvider);
    final dataAsync = ref.watch(_dairyCollectionsProvider(filter));
    final formAsync = ref.watch(collectionFormDataProvider);

    // Extract shift list from form data for labels
    final shiftItems = formAsync.maybeWhen(
      data: (d) => (d['shifts'] as List? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map)).toList(),
      orElse: () => <Map<String, dynamic>>[],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SyncStatusBar(),
            Expanded(
              child: RefreshIndicator(
                color: WakulimaColors.primary700,
                onRefresh: () async =>
                    ref.invalidate(_dairyCollectionsProvider(filter)),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateRow(filter),
                      const SizedBox(height: 16),
                      _buildFarmerField(),
                      const SizedBox(height: 16),
                      _buildShiftToggle(shiftItems),
                      const SizedBox(height: 20),
                      dataAsync.when(
                        loading: () => const _OverviewSkeleton(),
                        error:   (_, __) => _buildOverview(0, 0),
                        data:    (r) => _buildOverview(r.totalKg, r.entries.length),
                      ),
                      const SizedBox(height: 12),
                      _buildOfflineActions(),
                      const SizedBox(height: 8),
                      dataAsync.when(
                        loading: () => const _ListSkeleton(),
                        error:   (e, _) => _buildError(e.toString()),
                        data:    (r) => _buildCollectionsList(r.entries),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/collection'),
        backgroundColor: WakulimaColors.primary700,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 22, color: WakulimaColors.ink),
            onPressed: () => context.go('/dashboard'),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_formattedDateTime,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                    fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Row(children: [
            Text(_routeName ?? 'WAKULIMA DEV',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft)),
            const SizedBox(width: 8),
            StreamBuilder<SyncStatus>(
              stream: SyncEngine().statusStream,
              builder: (_, __) {
                final online = SyncEngine().isOnline;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: online ? WakulimaColors.primary50 : const Color(0xFFFFEEEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    Container(width: 6, height: 6,
                        decoration: BoxDecoration(
                            color: online ? WakulimaColors.primary700 : WakulimaColors.error,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(online ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: online ? WakulimaColors.primary700 : WakulimaColors.error)),
                  ]),
                );
              },
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Date Row ──────────────────────────────────────────────────────────────

  Widget _buildDateRow(_DairyFilter filter) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Date', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
          fontWeight: FontWeight.w600, color: WakulimaColors.inkMid)),
      const SizedBox(height: 8),
      Row(children: [
        GestureDetector(
          onTap: () => _showPresetMenu(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: WakulimaColors.border)),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: WakulimaColors.inkSoft),
              const SizedBox(width: 6),
              Text(_datePreset, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w500, color: WakulimaColors.ink)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: WakulimaColors.inkMuted),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(
          onTap: () => _pickDate(true),
          child: _dateChip(filter.from),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
            child: const Icon(Icons.arrow_forward, size: 14, color: WakulimaColors.inkMuted)),
        Expanded(child: GestureDetector(
          onTap: () => _pickDate(false),
          child: _dateChip(filter.to),
        )),
      ]),
    ]);
  }

  Widget _dateChip(String date) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WakulimaColors.border)),
    child: Text(date, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
        color: WakulimaColors.ink)),
  );

  void _showPresetMenu() {
    final items = ['Today', 'Yesterday', 'This Week', 'This Month'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Select Period', style: TextStyle(fontFamily: 'Poppins',
              fontSize: 15, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          const SizedBox(height: 12),
          ...items.map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item, style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: _datePreset == item ? FontWeight.w600 : FontWeight.w400,
                    color: _datePreset == item ? WakulimaColors.primary700 : WakulimaColors.ink)),
                trailing: _datePreset == item
                    ? const Icon(Icons.check, color: WakulimaColors.primary700, size: 18)
                    : null,
                onTap: () { Navigator.pop(context); _applyPreset(item); },
              )),
        ]),
      ),
    );
  }

  // ── Farmer Field (searchable) ─────────────────────────────────────────────

  Widget _buildFarmerField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Farmer', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
          fontWeight: FontWeight.w600, color: WakulimaColors.inkMid)),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _showFarmerPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _selectedFarmerId != null
                ? WakulimaColors.primary700
                : WakulimaColors.border,
                width: _selectedFarmerId != null ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(Icons.person_search_outlined, size: 18,
                color: _selectedFarmerId != null
                    ? WakulimaColors.primary700
                    : WakulimaColors.inkMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _selectedFarmerName ?? 'Search farmer…',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: _selectedFarmerName != null
                      ? WakulimaColors.ink
                      : WakulimaColors.inkMuted),
            )),
            if (_selectedFarmerId != null)
              GestureDetector(
                onTap: () {
                  setState(() { _selectedFarmerId = null; _selectedFarmerName = null; });
                  _updateFilter(ref.read(_dairyFilterProvider)
                      .copyWith(farmerId: null));
                },
                child: const Icon(Icons.close, size: 16, color: WakulimaColors.inkMuted),
              )
            else
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18,
                  color: WakulimaColors.inkMuted),
          ]),
        ),
      ),
    ]);
  }

  // ── Shift Toggle ──────────────────────────────────────────────────────────

  Widget _buildShiftToggle(List<Map<String, dynamic>> shiftItems) {
    // Build labels: All + each shift from API (max 2 shown as Morning/Evening)
    final labels = ['All', ...shiftItems.take(2).map((s) =>
        (s['description'] as String?) ?? 'Shift ${s['id']}')];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Shift', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
          fontWeight: FontWeight.w600, color: WakulimaColors.inkMid)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WakulimaColors.border)),
        child: Row(
          children: List.generate(labels.length, (i) {
            final selected = _shift == i;
            return Expanded(child: GestureDetector(
              onTap: () => _applyShift(i, shiftItems),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(3),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? WakulimaColors.primary700 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(labels[i], style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : WakulimaColors.inkSoft))),
              ),
            ));
          }),
        ),
      ),
    ]);
  }

  // ── Offline demo actions ──────────────────────────────────────────────────

  Widget _buildOfflineActions() {
    final isSyncing = _syncStatus == SyncStatus.syncing;
    final blocked   = _isSeeding || isSyncing;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Buttons row ──────────────────────────────────────────────────────
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: _isSeeding
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: WakulimaColors.inkSoft))
                : const Icon(Icons.add_circle_outline, size: 16),
            label: Text(
              _isSeeding
                  ? 'Seeding ${_seedCount}…'
                  : 'Seed ${MilkCollectionLocalRepository.demoTargetCount} Demo',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              foregroundColor: WakulimaColors.inkSoft,
              side: const BorderSide(color: WakulimaColors.border),
            ),
            onPressed: blocked ? null : _seedDummyCollections,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            icon: isSyncing
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: Colors.white))
                : const Icon(Icons.sync, size: 16),
            label: Text(isSyncing ? 'Syncing…' : 'Simulate Sync',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              backgroundColor: WakulimaColors.primary700,
            ),
            onPressed: blocked ? null : () => SyncEngine().syncNow(),
          ),
        ),
      ]),

      // ── Seed progress bar ─────────────────────────────────────────────
      if (_isSeeding) ...[
        const SizedBox(height: 8),
        _buildProgressBar(
          fraction: _seedFraction,
          done:     _seedCount,
          total:    MilkCollectionLocalRepository.demoTargetCount,
          label:    'Seeding offline records',
          color:    WakulimaColors.inkSoft,
        ),
      ],

      // ── Sync progress bar ─────────────────────────────────────────────
      if (isSyncing && _syncProgress != null) ...[
        const SizedBox(height: 8),
        _buildProgressBar(
          fraction: _syncProgress!.fraction,
          done:     _syncProgress!.done,
          total:    _syncProgress!.total,
          label:    _syncProgress!.currentItem ?? 'Syncing…',
          color:    WakulimaColors.primary700,
        ),
      ],
    ]);
  }

  Widget _buildProgressBar({
    required double fraction,
    required int    done,
    required int    total,
    required String label,
    required Color  color,
  }) {
    final pct = (fraction * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: WakulimaColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$pct%',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 3),
      Text('$label  ($done / $total)',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: WakulimaColors.inkMuted),
          overflow: TextOverflow.ellipsis),
    ]);
  }

  // ── Overview ──────────────────────────────────────────────────────────────

  Widget _buildOverview(double totalKg, int count) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Overview', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
          fontWeight: FontWeight.w600, color: WakulimaColors.inkMid)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WakulimaColors.border)),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 18, color: WakulimaColors.inkMuted),
          const SizedBox(width: 6),
          Text('${totalKg.toStringAsFixed(1)} KGs',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
          const SizedBox(width: 20),
          const Icon(Icons.description_outlined, size: 18, color: WakulimaColors.inkMuted),
          const SizedBox(width: 6),
          Text('$count ${count == 1 ? 'Entry' : 'Entries'}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
          const Spacer(),
          GestureDetector(
            onTap: () {},
            child: const Text('Print All', style: TextStyle(fontFamily: 'Poppins',
                fontSize: 13, fontWeight: FontWeight.w600,
                color: WakulimaColors.primary600)),
          ),
        ]),
      ),
    ]);
  }

  // ── Collections List ──────────────────────────────────────────────────────

  Widget _buildCollectionsList(List<_CollectionEntry> allEntries) {
    // Filter by search query
    final filtered = _searchQuery.isEmpty
        ? allEntries
        : allEntries.where((e) =>
            e.farmerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            e.farmerNo.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    // Pagination
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 9999);
    final safePage   = _page.clamp(0, totalPages - 1);
    final start      = safePage * _pageSize;
    final end        = (start + _pageSize).clamp(0, filtered.length);
    final pageItems  = filtered.sublist(start, end);

    final dupCount = allEntries.where((e) => e.isDuplicate).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row
      Row(children: [
        const Text('Milk Collections', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 13, fontWeight: FontWeight.w600, color: WakulimaColors.inkMid)),
        const Spacer(),
        if (dupCount > 0) ...[
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$dupCount dup${dupCount == 1 ? '' : 's'}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    fontWeight: FontWeight.w700, color: Color(0xFFF59E0B))),
          ),
        ],
        Text('${filtered.length} record${filtered.length == 1 ? '' : 's'}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: WakulimaColors.inkMuted)),
      ]),
      const SizedBox(height: 8),

      // Search field
      TextField(
        onChanged: (v) => setState(() { _searchQuery = v; _page = 0; }),
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search farmer name or no…',
          hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: WakulimaColors.inkMuted),
          prefixIcon: const Icon(Icons.search, size: 18, color: WakulimaColors.inkMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16, color: WakulimaColors.inkMuted),
                  onPressed: () => setState(() { _searchQuery = ''; _page = 0; }),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: WakulimaColors.primary700, width: 1.5)),
        ),
      ),
      const SizedBox(height: 8),

      // List
      if (filtered.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WakulimaColors.border)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.water_drop_outlined, size: 40,
                color: WakulimaColors.inkMuted.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(_searchQuery.isEmpty ? 'No collections recorded' : 'No results for "$_searchQuery"',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: WakulimaColors.inkMuted)),
          ]),
        )
      else
        Container(
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WakulimaColors.border)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pageItems.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: WakulimaColors.border),
            itemBuilder: (_, i) => _buildEntryTile(pageItems[i]),
          ),
        ),

      // Pagination controls
      if (filtered.length > _pageSize) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: safePage > 0
                ? () => setState(() => _page = safePage - 1)
                : null,
            color: WakulimaColors.primary700,
          ),
          Text('Page ${safePage + 1} of $totalPages',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w500, color: WakulimaColors.ink)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: safePage < totalPages - 1
                ? () => setState(() => _page = safePage + 1)
                : null,
            color: WakulimaColors.primary700,
          ),
        ]),
      ],
    ]);
  }

  Widget _buildEntryTile(_CollectionEntry e) {
    final dupColor = const Color(0xFFF59E0B); // amber
    return Container(
      color: e.isDuplicate ? dupColor.withOpacity(0.06) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        // Icon (red tint for duplicates)
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: e.isDuplicate
                ? dupColor.withOpacity(0.15)
                : WakulimaColors.primary50,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            e.isDuplicate ? Icons.warning_amber_rounded : Icons.water_drop_outlined,
            size: 18,
            color: e.isDuplicate ? dupColor : WakulimaColors.primary700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(e.farmerName,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: WakulimaColors.ink),
                  overflow: TextOverflow.ellipsis),
            ),
            if (e.isDuplicate)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dupColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('DUPLICATE',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                        fontWeight: FontWeight.w700, color: dupColor)),
              ),
          ]),
          Text('${e.farmerNo}  ·  ${e.shift}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkMuted)),
          Text(_fmtDateTime(e.createdAt),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkMuted)),
        ])),
        Text('${e.qty.toStringAsFixed(1)} kg',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.w700,
                color: e.isDuplicate ? dupColor : WakulimaColors.primary700)),
      ]),
    );
  }

  Widget _buildError(String msg) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border)),
    child: Row(children: [
      const Icon(Icons.error_outline, color: WakulimaColors.error, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text('Failed to load data',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: WakulimaColors.error))),
      TextButton(
        onPressed: () => ref.invalidate(
            _dairyCollectionsProvider(ref.read(_dairyFilterProvider))),
        child: const Text('Retry'),
      ),
    ]),
  );
}

// ── Skeletons ─────────────────────────────────────────────────────────────────

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();
  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border)),
    child: const Center(child: SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2,
            color: WakulimaColors.primary700))),
  );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();
  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border)),
    child: const Center(child: SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2,
            color: WakulimaColors.primary700))),
  );
}
