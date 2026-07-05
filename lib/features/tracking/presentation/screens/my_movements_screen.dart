import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/theme/app_theme.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _DayRoute {
  final String date;
  final double distanceKm;
  final int pointCount;
  const _DayRoute({required this.date, required this.distanceKm, required this.pointCount});
}

class _Position {
  final double lat, lon, speed;
  final DateTime fixTime;
  const _Position({required this.lat, required this.lon, required this.speed, required this.fixTime});
}

class _RouteDay {
  final _DayRoute day;
  final List<_Position> positions;
  const _RouteDay(this.day, this.positions);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _api = ApiClient();

Future<List<_DayRoute>> _fetchHistory() async {
  try {
    final resp = await _api.get('/tracking/me/history');
    final body = resp.data as Map?;
    final history = (body?['data']?['history'] as List?) ?? [];
    return history.map((h) => _DayRoute(
      date:       h['date'] as String,
      distanceKm: (h['distance_km'] as num).toDouble(),
      pointCount: h['point_count'] as int,
    )).toList();
  } catch (_) { return []; }
}

Future<_RouteDay?> _fetchDay(String date) async {
  try {
    final resp = await _api.get('/tracking/me', params: {'date': date});
    final body = resp.data as Map?;
    final data  = body?['data'] as Map?;
    final dist  = data?['distance']  as Map?;
    final rawPos = (data?['positions'] as List?) ?? [];
    final positions = rawPos.map((p) => _Position(
      lat:     (p['latitude']  as num).toDouble(),
      lon:     (p['longitude'] as num).toDouble(),
      speed:   (p['speed']     as num? ?? 0).toDouble(),
      fixTime: DateTime.tryParse(p['fix_time'] as String? ?? '') ?? DateTime.now(),
    )).toList();
    final day = _DayRoute(
      date:       date,
      distanceKm: (dist?['distance_km'] as num? ?? 0).toDouble(),
      pointCount: positions.length,
    );
    return _RouteDay(day, positions);
  } catch (_) { return null; }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MyMovementsScreen extends ConsumerStatefulWidget {
  const MyMovementsScreen({super.key});
  @override
  ConsumerState<MyMovementsScreen> createState() => _MyMovementsScreenState();
}

class _MyMovementsScreenState extends ConsumerState<MyMovementsScreen> {
  List<_DayRoute> _history = [];
  _RouteDay? _selected;
  bool _loadingHistory = true;
  bool _loadingDay = false;
  String? _userName;

  @override
  void initState() {
    super.initState();
    final user = Hive.box('auth').get('user') as Map?;
    _userName = user?['real_name']?.toString();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final h = await _fetchHistory();
    if (!mounted) return;
    setState(() { _history = h; _loadingHistory = false; });
    if (h.isNotEmpty) _loadDay(h.first.date);
  }

  Future<void> _loadDay(String date) async {
    setState(() => _loadingDay = true);
    final rd = await _fetchDay(date);
    if (!mounted) return;
    setState(() { _selected = rd; _loadingDay = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WakulimaColors.cream,
      appBar: AppBar(
        backgroundColor: WakulimaColors.primary700,
        foregroundColor: Colors.white,
        title: Text(_userName != null ? '$_userName — My Movements' : 'My Movements',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHistory),
        ],
      ),
      body: _loadingHistory
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? _buildEmpty()
              : Column(children: [
                  _buildTodayCard(),
                  _buildRouteTimeline(),
                  const Divider(height: 1),
                  _buildHistoryList(),
                ]),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.route_outlined, size: 64, color: WakulimaColors.inkMuted),
      const SizedBox(height: 16),
      Text('No movement recorded yet', style: TextStyle(fontFamily: 'Poppins', color: WakulimaColors.inkSoft, fontSize: 15)),
      const SizedBox(height: 8),
      Text('GPS sync starts after login', style: TextStyle(fontFamily: 'Poppins', color: WakulimaColors.inkMuted, fontSize: 13)),
    ]),
  );

  // ── Today card ─────────────────────────────────────────────────────────────

  Widget _buildTodayCard() {
    final today = _history.firstWhere(
      (h) => h.date == DateFormat('yyyy-MM-dd').format(DateTime.now()),
      orElse: () => _DayRoute(date: '', distanceKm: 0, pointCount: 0),
    );
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [WakulimaColors.primary700, WakulimaColors.primary700.withOpacity(0.8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: WakulimaColors.primary700.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TODAY', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text('${today.distanceKm.toStringAsFixed(2)} km',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 4),
          Text('${today.pointCount} GPS points', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
        ])),
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.directions_run_rounded, size: 32, color: Colors.white),
        ),
      ]),
    );
  }

  // ── Route timeline for selected day ────────────────────────────────────────

  Widget _buildRouteTimeline() {
    if (_loadingDay) return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
    if (_selected == null || _selected!.positions.isEmpty) return const SizedBox.shrink();

    final positions = _selected!.positions;
    final first     = positions.first;
    final last      = positions.last;
    final km        = _selected!.day.distanceKm;
    final date      = _selected!.day.date;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WakulimaColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.map_outlined, size: 16, color: WakulimaColors.primary700),
          const SizedBox(width: 6),
          Text(date, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: WakulimaColors.primary50, borderRadius: BorderRadius.circular(20)),
            child: Text('${km.toStringAsFixed(2)} km', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
          ),
        ]),
        const SizedBox(height: 12),
        _TimelineStop(
          icon: Icons.home_rounded,
          color: WakulimaColors.primary700,
          label: 'Start',
          time: DateFormat('HH:mm').format(first.fixTime),
          coords: '${first.lat.toStringAsFixed(5)}, ${first.lon.toStringAsFixed(5)}',
        ),
        // Intermediate stops (show max 3 evenly spaced)
        ..._intermediateStops(positions),
        _TimelineStop(
          icon: Icons.location_pin,
          color: Colors.redAccent,
          label: 'Latest',
          time: DateFormat('HH:mm').format(last.fixTime),
          coords: '${last.lat.toStringAsFixed(5)}, ${last.lon.toStringAsFixed(5)}',
          isLast: true,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.speed_rounded, size: 14, color: WakulimaColors.inkMuted),
          const SizedBox(width: 4),
          Text('Max speed: ${positions.map((p) => p.speed).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} km/h',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkSoft)),
          const SizedBox(width: 16),
          Icon(Icons.my_location_rounded, size: 14, color: WakulimaColors.inkMuted),
          const SizedBox(width: 4),
          Text('${positions.length} points', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkSoft)),
        ]),
      ]),
    );
  }

  List<Widget> _intermediateStops(List<_Position> positions) {
    if (positions.length <= 2) return [];
    final n = positions.length;
    final indices = [n ~/ 4, n ~/ 2, 3 * n ~/ 4].where((i) => i > 0 && i < n - 1).toList();
    return indices.map((i) {
      final p = positions[i];
      final pct = (i / n * 100).toInt();
      return _TimelineStop(
        icon: Icons.radio_button_checked,
        color: WakulimaColors.inkMuted,
        label: '$pct%',
        time: DateFormat('HH:mm').format(p.fixTime),
        coords: '${p.speed.toStringAsFixed(1)} km/h',
      );
    }).toList();
  }

  // ── History list ───────────────────────────────────────────────────────────

  Widget _buildHistoryList() {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        itemCount: _history.length,
        itemBuilder: (_, i) {
          final h = _history[i];
          final isSelected = _selected?.day.date == h.date;
          return GestureDetector(
            onTap: () => _loadDay(h.date),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? WakulimaColors.primary50 : WakulimaColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? WakulimaColors.primary400 : WakulimaColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? WakulimaColors.primary700 : WakulimaColors.cream,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.route_rounded, size: 20, color: isSelected ? Colors.white : WakulimaColors.inkMuted),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_formatDate(h.date), style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
                  Text('${h.pointCount} GPS points', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkSoft)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${h.distanceKm.toStringAsFixed(2)} km',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
                  if (isSelected) const Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: WakulimaColors.primary700),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      final today = DateTime.now();
      if (d.year == today.year && d.month == today.month && d.day == today.day) return 'Today';
      if (d.year == today.year && d.month == today.month && d.day == today.day - 1) return 'Yesterday';
      return DateFormat('EEE, d MMM yyyy').format(d);
    } catch (_) { return iso; }
  }
}

// ── Timeline stop widget ──────────────────────────────────────────────────────

class _TimelineStop extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, time, coords;
  final bool isLast;
  const _TimelineStop({required this.icon, required this.color, required this.label, required this.time, required this.coords, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: color),
          ),
          if (!isLast) Expanded(child: Container(width: 1.5, color: WakulimaColors.border, margin: const EdgeInsets.symmetric(vertical: 2))),
        ]),
        const SizedBox(width: 10),
        Expanded(child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 12, top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
              const Spacer(),
              Text(time, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkMuted)),
            ]),
            Text(coords, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: WakulimaColors.inkSoft)),
          ]),
        )),
      ]),
    );
  }
}
