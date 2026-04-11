import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ── Tab definitions ────────────────────────────────────────────────────────────

enum _Tab { orders, sales, invoices, movement, returns }

extension _TabX on _Tab {
  String get label {
    switch (this) {
      case _Tab.orders:   return 'Orders';
      case _Tab.sales:    return 'Sales';
      case _Tab.invoices: return 'Invoices';
      case _Tab.movement: return 'Movement';
      case _Tab.returns:  return 'Returns';
    }
  }

  String get endpoint {
    switch (this) {
      case _Tab.orders:   return '/sales/orders';
      case _Tab.sales:    return '/sales/invoices';
      case _Tab.invoices: return '/sales/invoices';
      case _Tab.movement: return '/sales/deliveries';
      case _Tab.returns:  return '/sales/credit-notes';
    }
  }

  Map<String, String> params(String dateFrom, String dateTo) {
    switch (this) {
      case _Tab.orders:
        return {'date_from': dateFrom, 'date_to': dateTo, 'per_page': '200'};
      case _Tab.sales:
        // Direct invoices: no linked order (so_id = null effectively — filter client-side)
        return {'date_from': dateFrom, 'date_to': dateTo, 'per_page': '200'};
      case _Tab.invoices:
        return {'date_from': dateFrom, 'date_to': dateTo, 'status': 'placed', 'per_page': '200'};
      case _Tab.movement:
        return {'date_from': dateFrom, 'date_to': dateTo, 'per_page': '200'};
      case _Tab.returns:
        return {'date_from': dateFrom, 'date_to': dateTo, 'cn_type': 'return', 'per_page': '200'};
    }
  }

  String get refField {
    switch (this) {
      case _Tab.orders:   return 'so_no';
      case _Tab.sales:    return 'inv_no';
      case _Tab.invoices: return 'inv_no';
      case _Tab.movement: return 'dn_no';
      case _Tab.returns:  return 'cn_no';
    }
  }

  String get dateField {
    switch (this) {
      case _Tab.orders:   return 'order_date';
      case _Tab.sales:    return 'invoice_date';
      case _Tab.invoices: return 'invoice_date';
      case _Tab.movement: return 'delivery_date';
      case _Tab.returns:  return 'cn_date';
    }
  }

  String get emptyMsg => 'No ${label.toLowerCase()} in the last 7 days';
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _tabDataProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, _Tab>((ref, tab) async {
  final api   = ref.watch(apiClientProvider);
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final weekAgo = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7)));
  try {
    final res  = await api.get(tab.endpoint, params: tab.params(weekAgo, today))
        .timeout(const Duration(seconds: 15));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final data = body['data'];
    List raw = [];
    if (data is List) raw = data;
    if (data is Map && data['data'] is List) raw = data['data'] as List;

    final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // For "Sales" tab filter to direct invoices only (no so_id, no dn_id)
    if (tab == _Tab.sales) {
      return list.where((r) => r['so_id'] == null && r['dn_id'] == null).toList();
    }
    return list;
  } catch (_) {
    return [];
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();

  static const _tabs = _Tab.values;

  static const _quickActions = [
    _QAItem('Order Entry',      Icons.receipt_long_outlined,   _QAItem.green,    false, '/sales/orders'),
    _QAItem('Direct Sale',      Icons.shopping_cart_outlined,  _QAItem.orange,   false, '/sales/direct-sale'),
    _QAItem('Sale Invoice',     Icons.description_outlined,    _QAItem.teal,     false, '/sales/invoices'),
    _QAItem('POS',              Icons.lock_outline,            null,             true,  null),
    _QAItem('Return Item',      Icons.keyboard_return_outlined, _QAItem.blue,   false, '/sales/returns'),
    _QAItem('Direct Delivery',  Icons.local_shipping_outlined, _QAItem.tealDark, false, '/sales/delivery'),
    _QAItem('Dispatch',         Icons.local_shipping_rounded,  _QAItem.green,    false, '/sales/dispatch'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _formattedDate {
    final now = DateTime.now();
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h    = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m    = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    return '${months[now.month]} ${now.day}, ${now.year}  $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildQuickActions(),
                _buildTabSection(),
              ]),
            ),
          ),
        ]),
      ),
      floatingActionButton: SizedBox(
        height: 40,
        child: FloatingActionButton.extended(
          onPressed: () {},
          backgroundColor: WakulimaColors.primary700,
          elevation: 2,
          icon: const Icon(Icons.directions_car_outlined, color: Colors.white, size: 16),
          label: const Text('Start Trip',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                  color: Colors.white, fontSize: 12)),
        ),
      ),
    );
  }

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
            Text(_formattedDate,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 17,
                    fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Row(children: [
            const Text('WAKULIMA DEV ',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: WakulimaColors.primary50,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: WakulimaColors.primary700, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('ONLINE',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Quick Actions',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: WakulimaColors.border, thickness: 1)),
        ]),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 12,
            crossAxisSpacing: 12, childAspectRatio: 1.55,
          ),
          itemCount: _quickActions.length,
          itemBuilder: (_, i) => _QuickActionCard(item: _quickActions[i]),
        ),
      ]),
    );
  }

  Widget _buildTabSection() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      color: Colors.white,
      child: Column(children: [
        TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w500),
          labelColor: WakulimaColors.sales,
          unselectedLabelColor: WakulimaColors.inkMuted,
          indicatorColor: WakulimaColors.sales,
          indicatorWeight: 2.5,
          dividerColor: WakulimaColors.border,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
        SizedBox(
          height: 500,
          child: TabBarView(
            controller: _tabCtrl,
            children: _tabs.map((t) => _TabContent(
              tab: t,
              searchCtrl: _searchCtrl,
              tabDataAsync: ref.watch(_tabDataProvider(t)),
              onRefresh: () => ref.invalidate(_tabDataProvider(t)),
            )).toList(),
          ),
        ),
      ]),
    );
  }
}

// ── Tab Content ────────────────────────────────────────────────────────────────

class _TabContent extends StatefulWidget {
  final _Tab tab;
  final TextEditingController searchCtrl;
  final AsyncValue<List<Map<String, dynamic>>> tabDataAsync;
  final VoidCallback onRefresh;
  const _TabContent({
    required this.tab, required this.searchCtrl,
    required this.tabDataAsync, required this.onRefresh,
  });

  @override
  State<_TabContent> createState() => _TabContentState();
}

class _TabContentState extends State<_TabContent> {
  static final _nf   = NumberFormat('#,##0.00', 'en_KE');
  static final _dfmt = DateFormat('dd MMM yyyy');
  final _localSearch = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchFocused = false;

  String _fmtDate(dynamic v) {
    if (v == null) return '—';
    try { return _dfmt.format(DateTime.parse(v.toString())); }
    catch (_) { return v.toString(); }
  }

  String _customerName(Map<String, dynamic> r) =>
      (r['customer'] as Map?)?['name']?.toString() ??
      r['debtor_no']?.toString() ?? '—';

  double _amount(Map<String, dynamic> r) =>
      (r['amount_total'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() => _searchFocused = _searchFocus.hasFocus));
  }

  @override
  void dispose() {
    _localSearch.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.tabDataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(
          color: WakulimaColors.primary700, strokeWidth: 2)),
      error: (_, __) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Failed to load data',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: WakulimaColors.error)),
          const SizedBox(height: 12),
          TextButton(onPressed: widget.onRefresh, child: const Text('Retry')),
        ]),
      ),
      data: (records) {
        // Filter by local search
        final q = _localSearch.text.toLowerCase();
        final filtered = q.isEmpty ? records : records.where((r) {
          final name  = _customerName(r).toLowerCase();
          final ref   = (r[widget.tab.refField]?.toString() ?? '').toLowerCase();
          return name.contains(q) || ref.contains(q);
        }).toList();

        final total   = records.fold(0.0, (s, r) => s + _amount(r));
        final average = records.isEmpty ? 0.0 : total / records.length;

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // KPI row
            Row(children: [
              Expanded(child: _StatCard(
                  label: 'Total ${widget.tab.label} Value',
                  value: 'KES ${_nf.format(total)}',
                  count: records.length,
                  period: 'Last 7 days')),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                  label: 'Avg ${widget.tab.label} Value',
                  value: 'KES ${_nf.format(average)}',
                  count: null,
                  period: 'Last 7 days')),
            ]),
            const SizedBox(height: 16),

            // ── Search bar ─────────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _searchFocused
                          ? WakulimaColors.primary700
                          : const Color(0xFFD8D8D8),
                      width: _searchFocused ? 2.0 : 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _searchFocused
                            ? WakulimaColors.primary700.withOpacity(0.10)
                            : Colors.black.withOpacity(0.05),
                        blurRadius: _searchFocused ? 10 : 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _searchFocused
                              ? WakulimaColors.primary700
                              : const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _searchFocused
                              ? Colors.white
                              : WakulimaColors.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Search ${widget.tab.label}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _searchFocused
                                    ? WakulimaColors.primary700
                                    : WakulimaColors.inkMuted,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            TextField(
                              controller: _localSearch,
                              focusNode: _searchFocus,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: WakulimaColors.ink,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Customer name or reference…',
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: WakulimaColors.inkMuted.withOpacity(0.7),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      if (_localSearch.text.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            _localSearch.clear();
                            _searchFocus.unfocus();
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEEEEE),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: WakulimaColors.inkSoft),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onRefresh,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: WakulimaColors.primary50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.refresh_rounded,
                              size: 18, color: WakulimaColors.primary700),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // List
            Expanded(child: filtered.isEmpty
                ? Center(
                    child: Text(widget.tab.emptyMsg,
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 13, color: WakulimaColors.inkMuted)))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r      = filtered[i];
                      final ref    = r[widget.tab.refField]?.toString() ?? '—';
                      final name   = _customerName(r);
                      final date   = _fmtDate(r[widget.tab.dateField]);
                      final amount = _amount(r);
                      final status = r['status']?.toString() ?? '';
                      return _RecordTile(
                        ref: ref, customerName: name, date: date,
                        amount: amount, status: status, tab: widget.tab,
                      );
                    },
                  )),
          ]),
        );
      },
    );
  }
}

// ── Record Tile ────────────────────────────────────────────────────────────────

class _RecordTile extends StatelessWidget {
  final String ref;
  final String customerName;
  final String date;
  final double amount;
  final String status;
  final _Tab tab;

  const _RecordTile({
    required this.ref, required this.customerName, required this.date,
    required this.amount, required this.status, required this.tab,
  });

  static final _nf = NumberFormat('#,##0.00', 'en_KE');

  @override
  Widget build(BuildContext context) {
    final sc = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WakulimaColors.border)),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: WakulimaColors.primary50,
              borderRadius: BorderRadius.circular(8)),
          child: Icon(_tabIcon(tab), size: 18, color: WakulimaColors.primary700),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ref,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          Text(customerName,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(date,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  color: WakulimaColors.inkMuted)),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('KES ${_nf.format(amount)}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          if (status.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: sc[0], borderRadius: BorderRadius.circular(20)),
              child: Text(status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w600, color: sc[1])),
            ),
        ]),
      ]),
    );
  }

  static IconData _tabIcon(_Tab t) {
    switch (t) {
      case _Tab.orders:   return Icons.receipt_long_outlined;
      case _Tab.sales:    return Icons.shopping_cart_outlined;
      case _Tab.invoices: return Icons.description_outlined;
      case _Tab.movement: return Icons.local_shipping_outlined;
      case _Tab.returns:  return Icons.keyboard_return_outlined;
    }
  }

  static List<Color> _statusColor(String s) {
    switch (s) {
      case 'placed':    return [const Color(0xFFEAF9EF), const Color(0xFF1A8F33)];
      case 'draft':     return [const Color(0xFFF5F5F5), const Color(0xFF757575)];
      case 'cancelled': return [const Color(0xFFFFEEEE), WakulimaColors.error];
      case 'invoiced':  return [const Color(0xFFEEF4FF), const Color(0xFF1565C0)];
      default:          return [const Color(0xFFFEF3CD), const Color(0xFF9A6B00)];
    }
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final int? count;
  final String period;
  const _StatCard({required this.label, required this.value, this.count, this.period = 'Today'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
            color: WakulimaColors.inkMuted)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
            fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
        const SizedBox(height: 4),
        if (count != null)
          Text('$count record${count != 1 ? 's' : ''} · $period',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  color: WakulimaColors.inkMuted))
        else
          Text(period,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  color: WakulimaColors.inkMuted)),
      ]),
    );
  }
}

// ── Quick Action Card (unchanged) ─────────────────────────────────────────────

class _QAItem {
  final String label;
  final IconData icon;
  final List<Color>? gradient;
  final bool locked;
  final String? route;
  const _QAItem(this.label, this.icon, this.gradient, this.locked, this.route);

  static const List<Color> green    = [Color(0xFF4CAF80), Color(0xFF2E7D52)];
  static const List<Color> orange   = [Color(0xFFFF9A5C), Color(0xFFFF6B35)];
  static const List<Color> teal     = [Color(0xFF4DD0C4), Color(0xFF26B5A8)];
  static const List<Color> blue     = [Color(0xFF5AB4F5), Color(0xFF2196F3)];
  static const List<Color> tealDark = [Color(0xFF26C6A8), Color(0xFF00897B)];
}

class _QuickActionCard extends StatefulWidget {
  final _QAItem item;
  const _QuickActionCard({super.key, required this.item});
  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0, upperBound: 0.04);
    _scale = Tween(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item     = widget.item;
    final isLocked = item.locked;

    return GestureDetector(
      onTapDown:  (_) => _ctrl.forward(),
      onTapUp:    (_) { _ctrl.reverse(); if (!isLocked && item.route != null) context.push(item.route!); },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: isLocked ? null : LinearGradient(
                colors: item.gradient!, begin: Alignment.topLeft, end: Alignment.bottomRight),
            color: isLocked ? const Color(0xFFF0F0F0) : null,
            border: isLocked ? Border.all(color: WakulimaColors.border, width: 1.5) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: isLocked ? Colors.white : Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle),
              child: Icon(item.icon, size: 22,
                  color: isLocked ? WakulimaColors.error.withOpacity(0.7) : Colors.white),
            ),
            const SizedBox(height: 10),
            Text(item.label,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLocked ? WakulimaColors.inkSoft : Colors.white)),
          ]),
        ),
      ),
    );
  }
}
