import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _analyticsFilterProvider = StateProvider<String>((_) => 'All');

final _purchasesProvider = FutureProvider.autoDispose<_PurchasesData>((ref) async {
  final filter = ref.watch(_analyticsFilterProvider);
  final api    = ref.watch(apiClientProvider);

  final box     = Hive.box('auth');
  final route   = box.get('route') as Map?;
  final routeId = (route?['id'] as num?)?.toInt();

  final now = DateTime.now();
  final fmt = (DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String from, to;
  switch (filter) {
    case 'Today':
      from = to = fmt(now);
      break;
    case 'This week':
      from = fmt(now.subtract(Duration(days: now.weekday - 1)));
      to   = fmt(now);
      break;
    case 'Pending':
      from = fmt(now.subtract(const Duration(days: 30)));
      to   = fmt(now);
      break;
    default: // All — last 30 days
      from = fmt(now.subtract(const Duration(days: 30)));
      to   = fmt(now);
  }

  final params = <String, dynamic>{'from': from, 'to': to, 'limit': '200'};
  if (routeId != null) params['route_id'] = routeId.toString();
  if (filter == 'Pending') params['status'] = 'submitted';

  try {
    final res  = await api.get('/farmers/milk-purchases', params: params)
        .timeout(const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return _PurchasesData.empty();

    final list = (body['data'] as List? ?? [])
        .map((p) => _Purchase.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();

    // Today count
    final todayStr   = fmt(now);
    final todayCount = list.where((p) => p.date == todayStr).length;

    // This week count
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekCount = list.where((p) {
      final d = DateTime.tryParse(p.date);
      return d != null && !d.isBefore(weekStart);
    }).length;

    final pendingCount = list.where((p) => p.status == 'submitted').length;

    // Aggregate KG per day
    final dailyMap = <String, double>{};
    for (final p in list) {
      dailyMap[p.date] = (dailyMap[p.date] ?? 0) + p.totalQty;
    }
    final dailyPoints = dailyMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Summary stats
    final totalKg     = list.fold(0.0, (s, p) => s + p.totalQty);
    final totalAmount = list.fold(0.0, (s, p) => s + p.totalAmount);
    final avgPerBatch = list.isEmpty ? 0.0 : totalKg / list.length;

    return _PurchasesData(
      purchases:    list,
      todayCount:   todayCount,
      weekCount:    weekCount,
      pendingCount: pendingCount,
      totalKg:      totalKg,
      totalAmount:  totalAmount,
      avgPerBatch:  avgPerBatch,
      dailyPoints:  dailyPoints,
    );
  } catch (_) {
    return _PurchasesData.empty();
  }
});

// ── Models ────────────────────────────────────────────────────────────────────

class _PurchasesData {
  final List<_Purchase>             purchases;
  final int                         todayCount;
  final int                         weekCount;
  final int                         pendingCount;
  final double                      totalKg;
  final double                      totalAmount;
  final double                      avgPerBatch;
  final List<MapEntry<String, double>> dailyPoints;

  const _PurchasesData({
    required this.purchases,
    required this.todayCount,
    required this.weekCount,
    required this.pendingCount,
    required this.totalKg,
    required this.totalAmount,
    required this.avgPerBatch,
    required this.dailyPoints,
  });

  factory _PurchasesData.empty() => const _PurchasesData(
    purchases:   [],
    todayCount:  0,
    weekCount:   0,
    pendingCount:0,
    totalKg:     0,
    totalAmount: 0,
    avgPerBatch: 0,
    dailyPoints: [],
  );
}

class _Purchase {
  final int    id;
  final String referenceNo;
  final String date;
  final String status;
  final double totalQty;
  final double totalAmount;
  final String routeName;

  const _Purchase({
    required this.id,
    required this.referenceNo,
    required this.date,
    required this.status,
    required this.totalQty,
    required this.totalAmount,
    required this.routeName,
  });

  factory _Purchase.fromJson(Map<String, dynamic> j) => _Purchase(
    id:          j['id'] as int? ?? 0,
    referenceNo: j['reference_no'] as String? ?? '—',
    date:        j['invoice_date'] as String? ?? '',
    status:      j['status'] as String? ?? 'submitted',
    totalQty:    (j['total_qty'] as num?)?.toDouble() ?? 0,
    totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
    routeName:   (j['route'] as Map?)?['route_name'] as String? ?? '—',
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter    = ref.watch(_analyticsFilterProvider);
    final dataAsync = ref.watch(_purchasesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 14),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 22, color: WakulimaColors.ink),
                  onPressed: () => context.go('/dashboard'),
                ),
                const Text('Analytics',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                        fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: WakulimaColors.primary600),
                  onPressed: () => ref.invalidate(_purchasesProvider),
                ),
              ]),
            ),

            Expanded(
              child: RefreshIndicator(
                color: WakulimaColors.primary700,
                onRefresh: () async => ref.invalidate(_purchasesProvider),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Summary bar (counts) ────────────────────────────
                      dataAsync.when(
                        loading: () => _SummaryBar(today: '—', week: '—', pending: '—'),
                        error:   (_, __) => _SummaryBar(today: '0', week: '0', pending: '0'),
                        data: (d) => _SummaryBar(
                          today:   d.todayCount.toString(),
                          week:    d.weekCount.toString(),
                          pending: d.pendingCount.toString(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── KPI stats cards ─────────────────────────────────
                      dataAsync.when(
                        loading: () => const _StatsRowShimmer(),
                        error:   (_, __) => const SizedBox.shrink(),
                        data: (d) => _StatsRow(data: d),
                      ),
                      const SizedBox(height: 16),

                      // ── Line chart ──────────────────────────────────────
                      dataAsync.when(
                        loading: () => _ChartPlaceholder(loading: true),
                        error:   (_, __) => _ChartPlaceholder(loading: false),
                        data: (d) => d.dailyPoints.isEmpty
                            ? _ChartPlaceholder(loading: false)
                            : _DailyChart(points: d.dailyPoints),
                      ),
                      const SizedBox(height: 16),

                      // ── Filter chips ────────────────────────────────────
                      _FilterRow(
                        selected: filter,
                        onSelect: (f) =>
                            ref.read(_analyticsFilterProvider.notifier).state = f,
                      ),
                      const SizedBox(height: 12),

                      // ── Purchases list ──────────────────────────────────
                      dataAsync.when(
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(
                                color: WakulimaColors.primary700, strokeWidth: 2),
                          ),
                        ),
                        error: (_, __) => _ErrorCard(
                            onRetry: () => ref.invalidate(_purchasesProvider)),
                        data: (d) {
                          if (d.purchases.isEmpty) {
                            return _EmptyState(
                              filter: filter,
                              onRetry: () => ref.invalidate(_purchasesProvider),
                            );
                          }
                          return Column(
                            children: d.purchases.map((p) =>
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _PurchaseTile(purchase: p),
                              )).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary Bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final String today, week, pending;
  const _SummaryBar({required this.today, required this.week, required this.pending});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WakulimaColors.primary700,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Expanded(child: _Stat(label: 'Today',     value: today)),
        Container(width: 1, height: 40, color: Colors.white24),
        Expanded(child: _Stat(label: 'This week', value: week)),
        Container(width: 1, height: 40, color: Colors.white24),
        Expanded(child: _Stat(label: 'Pending',   value: pending)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 20,
        fontWeight: FontWeight.w700, color: Colors.white)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
        color: Colors.white70)),
  ]);
}

// ── Stats Cards ───────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final _PurchasesData data;
  const _StatsRow({required this.data});

  static String _fmt(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _KpiCard(
          icon: Icons.water_drop,
          iconColor: WakulimaColors.primary600,
          iconBg: WakulimaColors.primary50,
          label: 'Total KG',
          value: '${_fmt(data.totalKg)} kg',
        )),
        const SizedBox(width: 10),
        Expanded(child: _KpiCard(
          icon: Icons.attach_money,
          iconColor: const Color(0xFF1A8F33),
          iconBg: const Color(0xFFEAF9EF),
          label: 'Total Amount',
          value: 'KES ${_fmt(data.totalAmount)}',
        )),
        const SizedBox(width: 10),
        Expanded(child: _KpiCard(
          icon: Icons.speed,
          iconColor: const Color(0xFF9A6B00),
          iconBg: const Color(0xFFFEF3CD),
          label: 'Avg / Batch',
          value: '${_fmt(data.avgPerBatch)} kg',
        )),
      ]),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String label, value;
  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
        const SizedBox(height: 1),
        Text(label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                color: WakulimaColors.inkMuted)),
      ]),
    );
  }
}

class _StatsRowShimmer extends StatelessWidget {
  const _StatsRowShimmer();

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(3, (i) => Expanded(
      child: Padding(
        padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: WakulimaColors.border,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    )));
  }
}

// ── Daily Line Chart ──────────────────────────────────────────────────────────

class _DailyChart extends StatelessWidget {
  final List<MapEntry<String, double>> points;
  const _DailyChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxY = points.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 10.0 : (maxY * 1.25).ceilToDouble();

    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i].value),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 6, bottom: 12),
          child: Text('KG Collected per Day',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
        ),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: 0,
              maxY: chartMax,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: chartMax / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: WakulimaColors.border,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: chartMax / 4,
                    getTitlesWidget: (value, _) => Text(
                      _fmtY(value),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 9,
                          color: WakulimaColors.inkMuted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: _xInterval(points.length).toDouble(),
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _shortDate(points[idx].key),
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 9,
                              color: WakulimaColors.inkMuted),
                        ),
                      );
                    },
                  ),
                ),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => WakulimaColors.primary700,
                  getTooltipItems: (spots) => spots.map((s) {
                    final idx = s.x.toInt();
                    final label = idx >= 0 && idx < points.length
                        ? _shortDate(points[idx].key)
                        : '';
                    return LineTooltipItem(
                      '$label\n${s.y.toStringAsFixed(1)} kg',
                      const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          fontWeight: FontWeight.w600, color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: WakulimaColors.primary700,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: points.length <= 14,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 3,
                      color: WakulimaColors.primary700,
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        WakulimaColors.primary700.withValues(alpha: 0.18),
                        WakulimaColors.primary700.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  static String _fmtY(double v) {
    if (v == 0) return '0';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  static String _shortDate(String iso) {
    // iso = "2025-04-09" → "Apr 9"
    try {
      final d = DateTime.parse(iso);
      const months = ['', 'Jan','Feb','Mar','Apr','May','Jun',
                          'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[d.month]} ${d.day}';
    } catch (_) { return iso; }
  }

  static int _xInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    return (count / 5).ceil();
  }
}

class _ChartPlaceholder extends StatelessWidget {
  final bool loading;
  const _ChartPlaceholder({required this.loading});

  @override
  Widget build(BuildContext context) => Container(
    height: 190,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: WakulimaColors.border),
    ),
    child: Center(child: loading
      ? const SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: WakulimaColors.primary700))
      : const Text('No chart data', style: TextStyle(
          fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted))),
  );
}

// ── Filter Row ────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _FilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const filters = ['All', 'Today', 'This week', 'Pending'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: filters.map((f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSelect(f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected == f ? WakulimaColors.primary700 : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected == f ? WakulimaColors.primary700 : WakulimaColors.border),
            ),
            child: Text(f, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected == f ? Colors.white : WakulimaColors.inkSoft)),
          ),
        ),
      )).toList()),
    );
  }
}

// ── Purchase Tile ─────────────────────────────────────────────────────────────

class _PurchaseTile extends StatelessWidget {
  final _Purchase purchase;
  const _PurchaseTile({required this.purchase});

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusStyle(purchase.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: WakulimaColors.primary50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Icon(Icons.water_drop_outlined,
                size: 20, color: WakulimaColors.primary700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(purchase.referenceNo,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
          const SizedBox(height: 2),
          Text('${purchase.date}  ·  ${purchase.routeName}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkMuted)),
          Text('${purchase.totalQty.toStringAsFixed(1)} KG  ·  KES ${purchase.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkSoft, fontWeight: FontWeight.w500)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusInfo[0] as Color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(statusInfo[2] as String,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: statusInfo[1] as Color)),
        ),
      ]),
    );
  }

  static List<Object> _statusStyle(String status) {
    switch (status) {
      case 'approved':
        return [const Color(0xFFEAF9EF), const Color(0xFF1A8F33), 'Approved'];
      case 'rejected':
        return [const Color(0xFFFFEEEE), WakulimaColors.error, 'Rejected'];
      default:
        return [const Color(0xFFFEF3CD), const Color(0xFF9A6B00), 'Pending'];
    }
  }
}

// ── Empty & Error ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String filter;
  final VoidCallback? onRetry;
  const _EmptyState({required this.filter, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 48),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.water_drop_outlined, size: 40,
          color: WakulimaColors.inkMuted.withValues(alpha: 0.4)),
      const SizedBox(height: 12),
      Text(
        filter == 'All'
            ? 'No milk purchases found'
            : 'No records for "$filter"',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
            color: WakulimaColors.inkMuted),
      ),
      if (onRetry != null) ...[
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins')),
        ),
      ],
    ]),
  );
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border)),
    child: Row(children: [
      const Icon(Icons.error_outline, color: WakulimaColors.error, size: 18),
      const SizedBox(width: 10),
      const Expanded(child: Text('Failed to load data',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: WakulimaColors.error))),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ]),
  );
}
