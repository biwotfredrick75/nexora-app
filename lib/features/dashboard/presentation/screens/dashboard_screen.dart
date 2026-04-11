import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/router/module_registry.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/app_constants.dart';
import 'package:wakulima/core/widgets/module_tile.dart';
import 'package:wakulima/core/widgets/stat_card.dart';

// ── Data models ──────────────────────────────────────────────────────────────

class _DashboardData {
  final double todayKg;
  final double todayAmount;
  final int    farmersCount;
  final List<_DayBar> weekBars;

  const _DashboardData({
    required this.todayKg,
    required this.todayAmount,
    required this.farmersCount,
    required this.weekBars,
  });

  factory _DashboardData.empty() => const _DashboardData(
      todayKg: 0, todayAmount: 0, farmersCount: 0, weekBars: []);
}

class _DayBar {
  final String label; // "Mon", "Tue" …
  final String dateKey; // "yyyy-MM-dd"
  final double kg;
  const _DayBar({required this.label, required this.dateKey, required this.kg});
}

// ── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _user = {};
  late Future<_DashboardData> _dataFuture;
  int _touchedIndex = -1;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('auth');
    final u = box.get('user');
    if (u is Map) _user = Map<String, dynamic>.from(u);
    _dataFuture = _loadDashboardData();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<_DashboardData> _loadDashboardData() async {
    final now   = DateTime.now();
    final today = _fmt(now);
    final from  = _fmt(now.subtract(const Duration(days: 6)));

    // Farmers count from Hive (populated at login)
    final box     = Hive.box('auth');
    final farmers = box.get('farmers');
    final farmersCount = farmers is List ? farmers.length : 0;

    try {
      final api = ApiClient();
      final res = await api.get('/farmers/milk-purchases', params: {
        'from':  from,
        'to':    today,
        'limit': '500',
      });
      final body = res.data as Map<String, dynamic>;
      if (body['success'] != true) return _DashboardData.empty();

      final purchases = (body['data'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      // Today totals
      double todayKg     = 0;
      double todayAmount = 0;
      for (final p in purchases) {
        if ((p['invoice_date'] as String? ?? '').startsWith(today)) {
          todayKg     += (p['total_qty']    as num? ?? 0).toDouble();
          todayAmount += (p['total_amount'] as num? ?? 0).toDouble();
        }
      }

      // Build 7-day bars (today = rightmost)
      const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final Map<String, double> kgByDate = {};
      for (final p in purchases) {
        final d = (p['invoice_date'] as String? ?? '').substring(0, 10);
        kgByDate[d] = (kgByDate[d] ?? 0) + (p['total_qty'] as num? ?? 0).toDouble();
      }

      final weekBars = List.generate(7, (i) {
        final date = now.subtract(Duration(days: 6 - i));
        final key  = _fmt(date);
        return _DayBar(
          label:   i == 6 ? 'Today' : dayNames[date.weekday - 1],
          dateKey: key,
          kg:      kgByDate[key] ?? 0,
        );
      });

      return _DashboardData(
        todayKg:      todayKg,
        todayAmount:  todayAmount,
        farmersCount: farmersCount,
        weekBars:     weekBars,
      );
    } catch (_) {
      return _DashboardData(
        todayKg:      0,
        todayAmount:  0,
        farmersCount: farmersCount,
        weekBars:     [],
      );
    }
  }

  void _refresh() => setState(() {
        _touchedIndex = -1;
        _dataFuture   = _loadDashboardData();
      });

  // ── Misc helpers ─────────────────────────────────────────────────────────

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: WakulimaColors.error),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await Hive.box('auth').clear();
      context.go('/login');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final name     = (_user['name'] as String? ?? 'User').split(' ').first;
    final station  = _user['station']   as String? ??
                     _user['loc_code']  as String? ?? 'Collection Point';
    final _av      = _user['avatar'] as String?;
    final initials = (_av != null && _av.isNotEmpty)
        ? _av
        : name.isNotEmpty
            ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
            : 'WK';

    return Scaffold(
      backgroundColor: WakulimaColors.cream,
      body: SafeArea(
        child: FutureBuilder<_DashboardData>(
          future: _dataFuture,
          builder: (context, snap) {
            final data    = snap.data ?? _DashboardData.empty();
            final loading = snap.connectionState == ConnectionState.waiting;

            return RefreshIndicator(
              color: WakulimaColors.primary700,
              onRefresh: () async => _refresh(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Header (white card) ──────────────────────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      color: WakulimaColors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // App-bar row
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Row(children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: WakulimaColors.primary700,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(Icons.water_drop,
                                    color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('WAKULIMA',
                                      style: TextStyle(
                                          fontFamily: 'Poppins', fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: WakulimaColors.primary700,
                                          letterSpacing: 1.5)),
                                  Text(station,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins', fontSize: 10,
                                          color: WakulimaColors.inkMuted)),
                                ],
                              ),
                              const Spacer(),
                              // Refresh button
                              IconButton(
                                icon: loading
                                    ? const SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: WakulimaColors.primary700))
                                    : const Icon(Icons.refresh_outlined,
                                        color: WakulimaColors.inkSoft),
                                onPressed: loading ? null : _refresh,
                              ),
                              GestureDetector(
                                onTap: _logout,
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: WakulimaColors.primary50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: WakulimaColors.primary200),
                                  ),
                                  child: Center(
                                    child: Text(initials,
                                        style: const TextStyle(
                                            fontFamily: 'Poppins', fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: WakulimaColors.primary700)),
                                  ),
                                ),
                              ),
                            ]),
                          ),

                          // Greeting + KPI cards
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$_greeting,',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 13,
                                        color: WakulimaColors.inkSoft)),
                                Text(name.toUpperCase(),
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: WakulimaColors.ink,
                                        letterSpacing: -0.3)),
                                const SizedBox(height: 16),
                                Row(children: [
                                  Expanded(child: StatCard(
                                    label: "Today's milk",
                                    value: loading
                                        ? '…'
                                        : _fmtKg(data.todayKg),
                                    unit: 'kg',
                                    icon: Icons.water_drop_outlined,
                                    color: WakulimaColors.collectionLite,
                                  )),
                                  const SizedBox(width: 10),
                                  Expanded(child: StatCard(
                                    label: 'Revenue today',
                                    value: loading
                                        ? '…'
                                        : AppFormatters.currencyCompact(
                                            data.todayAmount),
                                    unit: '',
                                    icon: Icons.trending_up,
                                    color: WakulimaColors.sales,
                                  )),
                                  const SizedBox(width: 10),
                                  Expanded(child: StatCard(
                                    label: 'Farmers',
                                    value: loading
                                        ? '…'
                                        : '${data.farmersCount}',
                                    unit: '',
                                    icon: Icons.people_outline,
                                    color: WakulimaColors.dairyAdmin,
                                  )),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Modules grid ─────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(children: [
                            const Text('Modules',
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontSize: 16, fontWeight: FontWeight.w700,
                                    color: WakulimaColors.ink)),
                            const Spacer(),
                            Text('${ModuleRegistry.all.length} available',
                                style: const TextStyle(fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: WakulimaColors.inkMuted)),
                          ]),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:  2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.25,
                          ),
                          itemCount: ModuleRegistry.all.length,
                          itemBuilder: (context, index) {
                            final module = ModuleRegistry.all[index];
                            return ModuleTile(
                              module: module,
                              onTap: () {
                                if (module.access == ModuleAccess.locked) {
                                  _showLockedDialog(module.title);
                                } else {
                                  context.go(module.route);
                                }
                              },
                            );
                          },
                        ),
                      ]),
                    ),
                  ),

                  // ── Daily collection chart ───────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverToBoxAdapter(
                      child: _buildDailyChart(data, loading),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Daily collection chart ───────────────────────────────────────────────

  Widget _buildDailyChart(_DashboardData data, bool loading) {
    return Container(
      decoration: BoxDecoration(
        color: WakulimaColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WakulimaColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.bar_chart_rounded,
                size: 18, color: WakulimaColors.primary700),
            const SizedBox(width: 8),
            const Text('Daily Collection (7 days)',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
            const Spacer(),
            Text('KG', style: TextStyle(fontFamily: 'Poppins',
                fontSize: 11, color: WakulimaColors.inkMuted)),
          ]),
          const SizedBox(height: 20),

          if (loading)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(
                  strokeWidth: 2, color: WakulimaColors.primary700)),
            )
          else if (data.weekBars.isEmpty ||
              data.weekBars.every((b) => b.kg == 0))
            SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_outlined,
                        size: 36,
                        color: WakulimaColors.inkMuted.withOpacity(0.4)),
                    const SizedBox(height: 8),
                    const Text('No data for the past 7 days',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            color: WakulimaColors.inkMuted)),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: _maxY(data.weekBars),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) =>
                          WakulimaColors.primary700.withOpacity(0.9),
                      getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                        '${rod.toY.toStringAsFixed(1)} kg',
                        const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    touchCallback: (event, response) {
                      setState(() {
                        _touchedIndex = response?.spot?.touchedBarGroupIndex ?? -1;
                      });
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= data.weekBars.length) {
                            return const SizedBox.shrink();
                          }
                          final isToday = i == data.weekBars.length - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              data.weekBars[i].label,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isToday ? 10 : 9,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isToday
                                    ? WakulimaColors.primary700
                                    : WakulimaColors.inkMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.min || value == meta.max) {
                            return Text(
                              value >= 1000
                                  ? '${(value / 1000).toStringAsFixed(1)}k'
                                  : value.toInt().toString(),
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 9,
                                  color: WakulimaColors.inkMuted),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        interval: _yInterval(data.weekBars),
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _yInterval(data.weekBars),
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: WakulimaColors.border,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(data.weekBars.length, (i) {
                    final bar     = data.weekBars[i];
                    final touched = i == _touchedIndex;
                    final isToday = i == data.weekBars.length - 1;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: bar.kg,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          color: touched
                              ? WakulimaColors.primary600
                              : isToday
                                  ? WakulimaColors.primary700
                                  : WakulimaColors.primary700
                                      .withOpacity(0.35),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: _maxY(data.weekBars),
                            color: WakulimaColors.primary50,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),

          // Summary row
          if (!loading && data.weekBars.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: WakulimaColors.primary50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.water_drop_outlined, size: 14,
                    color: WakulimaColors.primary700),
                const SizedBox(width: 6),
                Text(
                  'This week: ${_fmtKg(data.weekBars.fold(0.0, (s, b) => s + b.kg))} kg',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: WakulimaColors.primary700),
                ),
                const Spacer(),
                Text(
                  'Avg: ${_fmtKg(data.weekBars.isNotEmpty ? data.weekBars.fold(0.0, (s, b) => s + b.kg) / data.weekBars.length : 0)}/day',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: WakulimaColors.inkSoft),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _fmtKg(double kg) {
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k';
    return AppFormatters.number(kg);
  }

  static double _maxY(List<_DayBar> bars) {
    if (bars.isEmpty) return 100;
    final max = bars.fold(0.0, (m, b) => b.kg > m ? b.kg : m);
    if (max == 0) return 100;
    return (max * 1.25).ceilToDouble();
  }

  static double _yInterval(List<_DayBar> bars) {
    final max = _maxY(bars);
    if (max <= 100)  return 25;
    if (max <= 500)  return 100;
    if (max <= 2000) return 500;
    return 1000;
  }

  void _showLockedDialog(String moduleName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.lock_outline, color: WakulimaColors.inkMuted),
          const SizedBox(width: 10),
          Text(moduleName,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        ]),
        content: const Text(
          'This module is locked. Contact your administrator to enable access.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
