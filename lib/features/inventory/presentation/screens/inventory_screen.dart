import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ─── Theme colour ─────────────────────────────────────────────────────────────
const _inv = WakulimaColors.inventory; // teal

// ─── Providers ────────────────────────────────────────────────────────────────

final _kpiProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/kpis')
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] == true) return Map<String, dynamic>.from(b['data'] as Map);
  } catch (_) {}
  return {};
});

final _transfersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, status) async {
  final api  = ref.watch(apiClientProvider);
  final user = Hive.box('auth').get('user') as Map? ?? {};
  final loc  = user['loc_code']?.toString() ?? '';
  try {
    final p = <String, dynamic>{'per_page': '100'};
    if (status != 'all') p['status'] = status;
    final res = await api.get('/inventory/transfers', params: p)
        .timeout(const Duration(seconds: 15));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    final list = (raw is List ? raw : (raw is Map ? raw['data'] ?? [] : []))
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (loc.isEmpty) return list;
    return list
        .where((t) => t['from_location_id'] == loc || t['to_location_id'] == loc)
        .toList();
  } catch (_) {
    return [];
  }
});

final _locationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/locations')
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    return (b['data'] as List? ?? [])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .where((l) => l['inactive'] != true)
        .toList();
  } catch (_) {
    return [];
  }
});

final _itemSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, q) async {
  if (q.length < 2) return [];
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/items/search', params: {'q': q, 'per_page': '20'})
        .timeout(const Duration(seconds: 10));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    return (raw is List ? raw : (raw is Map ? raw['data'] ?? [] : []))
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
});

// Movement query key
class _MovKey {
  final String stockId, locCode, from, to;
  const _MovKey(this.stockId, this.locCode, this.from, this.to);
  @override
  bool operator ==(o) =>
      o is _MovKey &&
      o.stockId == stockId &&
      o.locCode == locCode &&
      o.from == from &&
      o.to == to;
  @override
  int get hashCode => Object.hash(stockId, locCode, from, to);
}

final _movementsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, _MovKey>(
        (ref, k) async {
  if (k.stockId.isEmpty) return {};
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/movements', params: {
      'stock_id': k.stockId,
      if (k.locCode.isNotEmpty) 'location_id': k.locCode,
      'from': k.from,
      'to': k.to,
    }).timeout(const Duration(seconds: 15));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] == true) return Map<String, dynamic>.from(b['data'] as Map);
  } catch (_) {}
  return {};
});

final _storeBalanceProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, stockId) async {
  if (stockId.isEmpty) return [];
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/items/$stockId/status')
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    return (b['data'] as List? ?? [])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .where((r) => (r['loc_code'] as String? ?? '').isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
});

// ─── Main Screen ──────────────────────────────────────────────────────────────

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  int _tab = 0; // 0=Requisition 1=Movements 2=Store

  Map get _user {
    final u = Hive.box('auth').get('user');
    return (u is Map) ? u : {};
  }

  String get _locCode => _user['loc_code']?.toString() ?? '';
  String get _userName => _user['name']?.toString() ?? 'User';

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final kpi = ref.watch(_kpiProvider).valueOrNull ?? {};
    final pendingTransfers = (kpi['pending_transfers'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(children: [
          _Header(
            greeting: _greeting,
            userName: _userName,
            locCode: _locCode,
            pendingTransfers: pendingTransfers,
          ),
          Expanded(child: _buildBody()),
          _buildActionBar(),
        ]),
      ),
      bottomNavigationBar: _BottomNav(
        selected: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case 0:
        return _RequisitionTab(locCode: _locCode);
      case 1:
        return _MovementsTab(userLocCode: _locCode);
      case 2:
        return _StoreTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildActionBar() {
    const teal2 = Color(0xFF00897B);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(children: [
        if (_tab == 0) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/inventory/transfer-request'),
              icon: const Icon(Icons.call_received_outlined, size: 14),
              label: const Text('Transfer Request',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: teal2,
                padding: const EdgeInsets.symmetric(vertical: 9),
                side: const BorderSide(color: teal2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push('/inventory/transfer'),
              icon: const Icon(Icons.call_made_outlined, size: 14),
              label: const Text('Transfer Out',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _inv,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ] else if (_tab == 1) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push('/inventory/transfer'),
              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
              label: const Text('Stock Transfer',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _inv,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ] else if (_tab == 2) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push('/inventory/transfer-request'),
              icon: const Icon(Icons.call_received_outlined, size: 14),
              label: const Text('Request Stock',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: teal2,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String greeting, userName, locCode;
  final int pendingTransfers;
  const _Header({
    required this.greeting,
    required this.userName,
    required this.locCode,
    required this.pendingTransfers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      color: WakulimaColors.inkMuted)),
              Text(userName,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 18,
                      fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
              const SizedBox(height: 3),
              Row(children: [
                const Text('WAKULIMA DEV ',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                            color: _inv, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('ONLINE',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w700, color: _inv)),
                  ]),
                ),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  border: Border.all(color: WakulimaColors.border, width: 1.5),
                  shape: BoxShape.circle),
              child: const Icon(Icons.person_outline_rounded,
                  size: 22, color: WakulimaColors.inkSoft),
            ),
            if (locCode.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _inv.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(locCode,
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w700, color: _inv)),
              ),
            ],
          ]),
        ]),
        if (pendingTransfers > 0) ...[
          const SizedBox(height: 10),
          _ActionChipsRow(pendingTransfers: pendingTransfers),
        ],
      ]),
    );
  }
}

class _ActionChipsRow extends StatelessWidget {
  final int pendingTransfers;
  const _ActionChipsRow({required this.pendingTransfers});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _ActionChip(
          icon: Icons.check_circle_outline,
          label: '$pendingTransfers: Pending Approval',
          color: const Color(0xFFFFF3CD),
          textColor: const Color(0xFF9A6B00),
        ),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.outbox_outlined,
          label: 'Issue Stock',
          color: _inv.withOpacity(0.1),
          textColor: _inv,
        ),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.move_to_inbox_outlined,
          label: 'Receive Stock',
          color: const Color(0xFFE8F5E9),
          textColor: const Color(0xFF2E7D52),
        ),
      ]),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, textColor;
  const _ActionChip(
      {required this.icon,
      required this.label,
      required this.color,
      required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: textColor),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: textColor)),
      ]),
    );
  }
}

// ─── Bottom Nav ───────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.selected, required this.onTap});

  static const _items = [
    (Icons.receipt_long_outlined, 'Requisition'),
    (Icons.local_shipping_outlined, 'Movements'),
    (Icons.storefront_outlined, 'Store'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: List.generate(_items.length, (i) {
          final active = selected == i;
          final item = _items[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                      color: active ? _inv.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20)),
                  child: Icon(item.$1,
                      size: 22,
                      color: active ? _inv : WakulimaColors.inkMuted),
                ),
                const SizedBox(height: 2),
                Text(item.$2,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? _inv : WakulimaColors.inkMuted)),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Small FAB ────────────────────────────────────────────────────────────────

class _SmallFab extends StatelessWidget {
  final String heroTag, label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SmallFab(
      {required this.heroTag,
      required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FloatingActionButton.extended(
        heroTag: heroTag,
        onPressed: onTap,
        backgroundColor: color,
        elevation: 2,
        icon: Icon(icon, color: Colors.white, size: 16),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 12)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — REQUISITION
// ═══════════════════════════════════════════════════════════════════════════════

class _RequisitionTab extends ConsumerStatefulWidget {
  final String locCode;
  const _RequisitionTab({required this.locCode});
  @override
  ConsumerState<_RequisitionTab> createState() => _RequisitionTabState();
}

class _RequisitionTabState extends ConsumerState<_RequisitionTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _statuses = const ['all', 'draft', 'pending', 'approved', 'rejected'];
  final _labels   = const ['All', 'Draft', 'Pending', 'Approved', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w400),
          labelColor: _inv,
          unselectedLabelColor: WakulimaColors.inkMuted,
          indicatorColor: _inv,
          indicatorWeight: 2.5,
          dividerColor: WakulimaColors.border,
          tabs: _labels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: _statuses
              .map((s) => _TransferList(
                    status: s,
                    locCode: widget.locCode,
                    onRefresh: () =>
                        ref.invalidate(_transfersProvider(s)),
                  ))
              .toList(),
        ),
      ),
    ]);
  }
}

class _TransferList extends ConsumerStatefulWidget {
  final String status, locCode;
  final VoidCallback onRefresh;
  const _TransferList(
      {required this.status,
      required this.locCode,
      required this.onRefresh});
  @override
  ConsumerState<_TransferList> createState() => _TransferListState();
}

class _TransferListState extends ConsumerState<_TransferList> {
  static const _pageSize = 20;
  int _visibleCount = _pageSize;

  static final _dfmt = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    return ref.watch(_transfersProvider(widget.status)).when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: _inv, strokeWidth: 2)),
      error: (_, __) => _ErrorState(onRetry: widget.onRefresh),
      data: (records) {
        if (records.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.swap_horiz_rounded,
                  size: 52, color: _inv.withOpacity(0.25)),
              const SizedBox(height: 12),
              Text(
                  widget.status == 'all'
                      ? 'No transfers for your location'
                      : 'No ${widget.status} transfers',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      color: WakulimaColors.inkMuted)),
            ]),
          );
        }

        final visible = records.take(_visibleCount).toList();
        final hasMore = records.length > _visibleCount;

        return RefreshIndicator(
          color: _inv,
          onRefresh: () async {
            setState(() => _visibleCount = _pageSize);
            widget.onRefresh();
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            itemCount: visible.length + (hasMore ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == visible.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _LoadMoreBtn(
                    remaining: records.length - _visibleCount,
                    onTap: () =>
                        setState(() => _visibleCount += _pageSize),
                  ),
                );
              }
              final t = visible[i];
              final isOut = t['from_location_id'] == widget.locCode;
              final tRef  = t['reference']?.toString() ?? '—';
              final from  = t['from_location_id']?.toString() ?? '—';
              final to    = t['to_location_id']?.toString() ?? '—';
              final st    = t['status']?.toString() ?? '';
              final date  = _fmt(t['date']);
              final items = (t['items'] as List?)?.length ?? 0;
              final sc    = _statusColor(st);
              final dc    = isOut ? const Color(0xFFE53935) : const Color(0xFF1565C0);
              final di    = isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WakulimaColors.border)),
                  child: Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                          color: dc.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(di, size: 20, color: dc),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(tRef,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: WakulimaColors.ink)),
                        const SizedBox(height: 3),
                        Row(children: [
                          _LocBadge(code: from),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 12, color: WakulimaColors.inkMuted),
                          ),
                          _LocBadge(code: to),
                        ]),
                        const SizedBox(height: 3),
                        Text('$date · $items item${items != 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 10,
                                color: WakulimaColors.inkMuted)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: sc[0],
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          st.isEmpty
                              ? '—'
                              : st[0].toUpperCase() + st.substring(1),
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w600, color: sc[1])),
                    ),
                  ]),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    try { return _dfmt.format(DateTime.parse(v.toString())); }
    catch (_) { return v.toString(); }
  }

  static List<Color> _statusColor(String s) {
    switch (s) {
      case 'approved': return [const Color(0xFFEAF9EF), const Color(0xFF1A8F33)];
      case 'pending':  return [const Color(0xFFFEF3CD), const Color(0xFF9A6B00)];
      case 'draft':    return [const Color(0xFFF5F5F5), const Color(0xFF757575)];
      case 'rejected': return [const Color(0xFFFFEEEE), WakulimaColors.error];
      default:         return [const Color(0xFFE8F4FD), const Color(0xFF1565C0)];
    }
  }
}

class _LocBadge extends StatelessWidget {
  final String code;
  const _LocBadge({required this.code});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(5)),
      child: Text(code,
          style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 10,
              fontWeight: FontWeight.w700, color: WakulimaColors.inkSoft)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — MOVEMENTS
// ═══════════════════════════════════════════════════════════════════════════════

class _MovementsTab extends ConsumerStatefulWidget {
  final String userLocCode;
  const _MovementsTab({required this.userLocCode});
  @override
  ConsumerState<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends ConsumerState<_MovementsTab> {
  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  String _itemQuery = '';
  String _selectedStockId = '';
  String _selectedStockDesc = '';
  bool _showItemDrop = false;

  String _selectedLoc = '';
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to   = DateTime.now();

  static final _df = DateFormat('yyyy-MM-dd');
  static final _dl = DateFormat('dd MMM');
  static final _nf = NumberFormat('#,##0.00', 'en_KE');

  @override
  void initState() {
    super.initState();
    _selectedLoc = widget.userLocCode;
    _itemFocus.addListener(() {
      if (!_itemFocus.hasFocus) setState(() => _showItemDrop = false);
    });
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  _MovKey get _key => _MovKey(
      _selectedStockId, _selectedLoc,
      _df.format(_from), _df.format(_to));

  @override
  Widget build(BuildContext context) {
    final locsAsync = ref.watch(_locationsProvider);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── Item Search ──────────────────────────────────────────────────────
        _SectionCard(
          title: 'Item',
          icon: Icons.inventory_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: [
              // Search field
              _SearchField(
                label: 'Search Item',
                hint: 'Item name or stock code…',
                controller: _itemCtrl,
                focusNode: _itemFocus,
                selectedCode: _selectedStockId.isNotEmpty ? _selectedStockId : null,
                onChanged: (v) => setState(() {
                  _itemQuery = v;
                  _showItemDrop = v.length >= 2;
                  if (_selectedStockId.isNotEmpty &&
                      v != '$_selectedStockId — $_selectedStockDesc') {
                    _selectedStockId = '';
                    _selectedStockDesc = '';
                  }
                }),
                onClear: () => setState(() {
                  _itemCtrl.clear();
                  _itemQuery = '';
                  _showItemDrop = false;
                  _selectedStockId = '';
                  _selectedStockDesc = '';
                }),
              ),
              // Dropdown
              if (_showItemDrop)
                _ItemDropdown(
                  query: _itemQuery,
                  onSelect: (sid, desc) {
                    _selectedStockId   = sid;
                    _selectedStockDesc = desc;
                    _itemCtrl.text     = '$sid — $desc';
                    _itemFocus.unfocus();
                    setState(() => _showItemDrop = false);
                  },
                ),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // ── Filters Row ──────────────────────────────────────────────────────
        Row(children: [
          // Location picker
          Expanded(
            child: _SectionCard(
              title: 'Location',
              icon: Icons.location_on_outlined,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: locsAsync.when(
                  loading: () => const SizedBox(
                      height: 36,
                      child: Center(child: LinearProgressIndicator())),
                  error: (_, __) => const Text('—'),
                  data: (locs) {
                    // Deduplicate by code to avoid DropdownButton assertion
                    final seen = <String>{};
                    final uniqueLocs = locs.where((l) {
                      final c = l['code']?.toString() ?? '';
                      return c.isNotEmpty && seen.add(c);
                    }).toList();
                    final validValue = _selectedLoc.isNotEmpty &&
                            uniqueLocs.any((l) => l['code'] == _selectedLoc)
                        ? _selectedLoc
                        : null;
                    return DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: validValue,
                        hint: const Text('All locations',
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 12)),
                        isExpanded: true,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            color: WakulimaColors.ink),
                        items: [
                          const DropdownMenuItem(
                              value: '',
                              child: Text('All locations',
                                  style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12))),
                          ...uniqueLocs.map((l) => DropdownMenuItem(
                              value: l['code']?.toString() ?? '',
                              child: Text(
                                  '${l['code']} — ${l['name']}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12),
                                  overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedLoc = v ?? ''),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // ── Date Range ───────────────────────────────────────────────────────
        _SectionCard(
          title: 'Date Range',
          icon: Icons.calendar_today_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Expanded(child: _DateBtn(
                  date: _from, label: 'From',
                  onPick: (d) => setState(() => _from = d))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 16, color: WakulimaColors.inkMuted),
              ),
              Expanded(child: _DateBtn(
                  date: _to, label: 'To',
                  onPick: (d) => setState(() => _to = d))),
            ]),
          ),
        ),
        const SizedBox(height: 14),

        // ── Results ──────────────────────────────────────────────────────────
        if (_selectedStockId.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            alignment: Alignment.center,
            child: Column(children: [
              Icon(Icons.inventory_2_outlined,
                  size: 52, color: _inv.withOpacity(0.25)),
              const SizedBox(height: 12),
              const Text('Search for an item to view movements',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      color: WakulimaColors.inkMuted)),
            ]),
          )
        else
          _MovementResults(movKey: _key),
      ],
    );
  }
}

class _ItemDropdown extends ConsumerWidget {
  final String query;
  final void Function(String stockId, String desc) onSelect;
  const _ItemDropdown({required this.query, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_itemSearchProvider(query)).when(
      loading: () => Container(
          height: 44, color: Colors.white,
          child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: _inv))),
      error: (_, __) => const SizedBox(),
      data: (results) => results.isEmpty
          ? Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: const Text('No items found',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      color: WakulimaColors.inkMuted)))
          : Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(10)),
                  border: Border.all(color: _inv.withOpacity(0.3)),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8, offset: const Offset(0, 4))]),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final it   = results[i];
                  final sid  = it['stock_id']?.toString() ?? '';
                  final desc = it['description']?.toString() ?? '';
                  return InkWell(
                    onTap: () => onSelect(sid, desc),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: _inv.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(5)),
                          child: Text(sid,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 10,
                                  fontWeight: FontWeight.w700, color: _inv)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(desc,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _MovementResults extends ConsumerWidget {
  final _MovKey movKey;
  const _MovementResults({required this.movKey});

  static final _nf  = NumberFormat('#,##0.00', 'en_KE');
  static final _dfmt = DateFormat('dd MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_movementsProvider(movKey)).when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: _inv, strokeWidth: 2)),
      error: (_, __) => const Center(
          child: Text('Failed to load movements',
              style: TextStyle(color: WakulimaColors.error))),
      data: (data) {
        if (data.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text('No stock movement on these dates',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13,
                    color: WakulimaColors.inkMuted)),
          );
        }

        final opening  = (data['opening_balance'] as num?)?.toDouble() ?? 0;
        final totalIn  = (data['total_in']  as num?)?.toDouble() ?? 0;
        final totalOut = (data['total_out'] as num?)?.toDouble() ?? 0;
        final closing  = (data['closing_balance'] as num?)?.toDouble() ?? 0;
        final rows     = data['movements'] as List? ?? [];

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Summary strip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _inv.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _inv.withOpacity(0.2))),
            child: Row(children: [
              _MovStat('Opening', opening, Colors.grey),
              _vDiv(),
              _MovStat('In', totalIn, const Color(0xFF1A8F33)),
              _vDiv(),
              _MovStat('Out', totalOut, WakulimaColors.error),
              _vDiv(),
              _MovStat('Closing', closing, _inv),
            ]),
          ),
          const SizedBox(height: 12),

          // Movement rows
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WakulimaColors.border)),
            child: Column(
              children: List.generate(rows.length, (i) {
                final r   = Map<String, dynamic>.from(rows[i] as Map);
                final qty = (r['qty'] as num?)?.toDouble() ?? 0;
                final bal = (r['balance'] as num?)?.toDouble() ?? 0;
                final type = r['type_label']?.toString() ?? '—';
                final ref  = r['reference']?.toString() ?? '—';
                final loc  = r['loc_code']?.toString() ?? '—';
                final date = r['tran_date']?.toString() ?? '—';
                final isIn = qty >= 0;

                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                      border: i < rows.length - 1
                          ? const Border(
                              bottom: BorderSide(color: Color(0xFFF0F0F0)))
                          : null),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: (isIn
                                  ? const Color(0xFF1A8F33)
                                  : WakulimaColors.error)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(
                          isIn
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 16,
                          color: isIn
                              ? const Color(0xFF1A8F33)
                              : WakulimaColors.error),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(type,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: WakulimaColors.ink)),
                        Text('$ref · $loc',
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 10,
                                color: WakulimaColors.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      Text(
                          '${isIn ? '+' : ''}${_nf.format(qty)}',
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isIn
                                  ? const Color(0xFF1A8F33)
                                  : WakulimaColors.error)),
                      Text('Bal: ${_nf.format(bal)}',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 10,
                              color: WakulimaColors.inkMuted)),
                    ]),
                  ]),
                );
              }),
            ),
          ),
        ]);
      },
    );
  }
}

class _MovStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MovStat(this.label, this.value, this.color);
  static final _nf = NumberFormat('#,##0', 'en_KE');

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(_nf.format(value),
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10,
                color: WakulimaColors.inkMuted)),
      ]),
    );
  }
}

Widget _vDiv() => Container(
    width: 1, height: 32,
    color: WakulimaColors.border.withOpacity(0.6),
    margin: const EdgeInsets.symmetric(horizontal: 4));

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — STORE
// ═══════════════════════════════════════════════════════════════════════════════

class _StoreTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends ConsumerState<_StoreTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w400),
          labelColor: _inv,
          unselectedLabelColor: WakulimaColors.inkMuted,
          indicatorColor: _inv,
          indicatorWeight: 2.5,
          dividerColor: WakulimaColors.border,
          tabs: const [
            Tab(text: 'Store Balance'),
            Tab(text: 'Stock Movements'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: const [
            _StoreBalanceTab(),
            _StockMovementReportTab(),
          ],
        ),
      ),
    ]);
  }
}

// ── Store Balance ──────────────────────────────────────────────────────────────

class _StoreBalanceTab extends ConsumerStatefulWidget {
  const _StoreBalanceTab();
  @override
  ConsumerState<_StoreBalanceTab> createState() => _StoreBalanceTabState();
}

class _StoreBalanceTabState extends ConsumerState<_StoreBalanceTab> {
  final _itemCtrl  = TextEditingController();
  final _itemFocus = FocusNode();
  String _itemQuery = '';
  String _selectedStockId   = '';
  String _selectedStockDesc = '';
  bool _showDrop = false;
  int _visibleCount = 15;

  static final _nf = NumberFormat('#,##0.00', 'en_KE');

  @override
  void initState() {
    super.initState();
    _itemFocus.addListener(() {
      if (!_itemFocus.hasFocus) setState(() => _showDrop = false);
    });
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── Item Search ────────────────────────────────────────────────────
        _SectionCard(
          title: 'Select Item',
          icon: Icons.inventory_2_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: [
              _SearchField(
                label: 'Select Item',
                hint: 'Type item name or stock code…',
                controller: _itemCtrl,
                focusNode: _itemFocus,
                selectedCode: _selectedStockId.isNotEmpty ? _selectedStockId : null,
                onChanged: (v) => setState(() {
                  _itemQuery = v;
                  _showDrop  = v.length >= 2;
                  if (_selectedStockId.isNotEmpty &&
                      v != '$_selectedStockId — $_selectedStockDesc') {
                    _selectedStockId   = '';
                    _selectedStockDesc = '';
                  }
                }),
                onClear: () => setState(() {
                  _itemCtrl.clear();
                  _itemQuery = '';
                  _showDrop  = false;
                  _selectedStockId   = '';
                  _selectedStockDesc = '';
                }),
              ),
              if (_showDrop)
                _ItemDropdown(
                  query: _itemQuery,
                  onSelect: (sid, desc) {
                    _selectedStockId   = sid;
                    _selectedStockDesc = desc;
                    _visibleCount      = 15;
                    _itemCtrl.text     = '$sid — $desc';
                    _itemFocus.unfocus();
                    setState(() => _showDrop = false);
                  },
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),

        // ── Balance Table ──────────────────────────────────────────────────
        if (_selectedStockId.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            alignment: Alignment.center,
            child: Column(children: [
              Icon(Icons.storefront_outlined,
                  size: 52, color: _inv.withOpacity(0.25)),
              const SizedBox(height: 12),
              const Text('Select an item to view store balances',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      color: WakulimaColors.inkMuted)),
            ]),
          )
        else
          Consumer(builder: (context, ref, _) {
            return ref.watch(_storeBalanceProvider(_selectedStockId)).when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: _inv, strokeWidth: 2)),
              error: (_, __) =>
                  const Center(child: Text('Failed to load balance')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('No stock found for this item',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              color: WakulimaColors.inkMuted)));
                }
                final total = rows.fold(
                    0.0,
                    (s, r) =>
                        s + ((r['qty_on_hand'] as num?)?.toDouble() ?? 0));
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Item header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: _inv.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _inv.withOpacity(0.2))),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: _inv.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(7)),
                        child: Text(_selectedStockId,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _inv)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_selectedStockDesc,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: WakulimaColors.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('Total: ${_nf.format(total)}',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _inv)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  // Store rows (paginated)
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: WakulimaColors.border)),
                    child: Column(
                      children: [
                        ...List.generate(
                            rows.length < _visibleCount
                                ? rows.length
                                : _visibleCount, (i) {
                          final r    = rows[i];
                          final loc  = r['loc_code']?.toString() ?? '—';
                          final name = r['location']?.toString() ?? '';
                          final qty  = (r['qty_on_hand'] as num?)?.toDouble() ?? 0;
                          final low  = qty <= 0;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                                border: i < (rows.length < _visibleCount
                                        ? rows.length
                                        : _visibleCount) - 1
                                    ? const Border(
                                        bottom: BorderSide(
                                            color: Color(0xFFF0F0F0)))
                                    : null),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF0F0F0),
                                    borderRadius:
                                        BorderRadius.circular(6)),
                                child: Text(loc,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: WakulimaColors.inkSoft)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                    name.isNotEmpty ? name : loc,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: WakulimaColors.ink)),
                              ),
                              Text(_nf.format(qty),
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: low
                                          ? WakulimaColors.error
                                          : WakulimaColors.ink)),
                            ]),
                          );
                        }),
                        if (rows.length > _visibleCount)
                          _LoadMoreBtn(
                            remaining: rows.length - _visibleCount,
                            onTap: () =>
                                setState(() => _visibleCount += 15),
                          ),
                      ],
                    ),
                  ),
                ]);
              },
            );
          }),
      ],
    );
  }
}

// ── Stock Movement Report (per date range, no item required) ──────────────────

class _StockMovementReportTab extends ConsumerStatefulWidget {
  const _StockMovementReportTab();
  @override
  ConsumerState<_StockMovementReportTab> createState() =>
      _StockMovementReportTabState();
}

class _StockMovementReportTabState
    extends ConsumerState<_StockMovementReportTab> {
  final _itemCtrl  = TextEditingController();
  final _itemFocus = FocusNode();
  String _itemQuery = '';
  String _stockId = '';
  String _stockDesc = '';
  bool _showDrop = false;
  String _locCode = '';
  DateTime _from = DateTime.now();
  DateTime _to   = DateTime.now();

  static final _df = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _itemFocus.addListener(() {
      if (!_itemFocus.hasFocus) setState(() => _showDrop = false);
    });
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locsAsync = ref.watch(_locationsProvider);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Item picker
        _SectionCard(
          title: 'Item',
          icon: Icons.inventory_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: [
              _SearchField(
                label: 'Search Item',
                hint: 'Item name or stock code…',
                controller: _itemCtrl,
                focusNode: _itemFocus,
                selectedCode: _stockId.isNotEmpty ? _stockId : null,
                onChanged: (v) => setState(() {
                  _itemQuery = v;
                  _showDrop  = v.length >= 2;
                  if (_stockId.isNotEmpty && v != '$_stockId — $_stockDesc') {
                    _stockId   = '';
                    _stockDesc = '';
                  }
                }),
                onClear: () => setState(() {
                  _itemCtrl.clear();
                  _itemQuery = '';
                  _showDrop  = false;
                  _stockId   = '';
                  _stockDesc = '';
                }),
              ),
              if (_showDrop)
                _ItemDropdown(
                  query: _itemQuery,
                  onSelect: (sid, desc) {
                    _stockId   = sid;
                    _stockDesc = desc;
                    _itemCtrl.text = '$sid — $desc';
                    _itemFocus.unfocus();
                    setState(() => _showDrop = false);
                  },
                ),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // Location + date
        Row(children: [
          Expanded(
            child: _SectionCard(
              title: 'Location',
              icon: Icons.location_on_outlined,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: locsAsync.when(
                  loading: () => const SizedBox(
                      height: 36,
                      child: Center(child: LinearProgressIndicator())),
                  error: (_, __) => const SizedBox(),
                  data: (locs) {
                    final seen2 = <String>{};
                    final uniqueLocs2 = locs.where((l) {
                      final c = l['code']?.toString() ?? '';
                      return c.isNotEmpty && seen2.add(c);
                    }).toList();
                    final validVal = _locCode.isNotEmpty &&
                            uniqueLocs2.any((l) => l['code'] == _locCode)
                        ? _locCode
                        : null;
                    return DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: validVal,
                        hint: const Text('All',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                        isExpanded: true,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            color: WakulimaColors.ink),
                        items: [
                          const DropdownMenuItem(
                              value: '',
                              child: Text('All',
                                  style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12))),
                          ...uniqueLocs2.map((l) => DropdownMenuItem(
                              value: l['code']?.toString() ?? '',
                              child: Text(l['code']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12)))),
                        ],
                        onChanged: (v) => setState(() => _locCode = v ?? ''),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        _SectionCard(
          title: 'Date Range',
          icon: Icons.date_range_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Expanded(child: _DateBtn(
                  date: _from, label: 'From',
                  onPick: (d) => setState(() => _from = d))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: WakulimaColors.inkMuted),
              ),
              Expanded(child: _DateBtn(
                  date: _to, label: 'To',
                  onPick: (d) => setState(() => _to = d))),
            ]),
          ),
        ),
        const SizedBox(height: 14),

        if (_stockId.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            alignment: Alignment.center,
            child: Column(children: [
              Icon(Icons.bar_chart_rounded,
                  size: 52, color: _inv.withOpacity(0.25)),
              const SizedBox(height: 12),
              const Text('Select an item to view stock movements',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: WakulimaColors.inkMuted)),
            ]),
          )
        else
          _MovementResults(
            movKey: _MovKey(_stockId, _locCode,
                _df.format(_from), _df.format(_to)),
          ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(children: [
            Icon(icon, size: 15, color: _inv),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700, color: _inv)),
          ]),
        ),
        Divider(height: 1, color: WakulimaColors.border.withOpacity(0.6)),
        child,
      ]),
    );
  }
}

class _DateBtn extends StatelessWidget {
  final DateTime date;
  final String label;
  final ValueChanged<DateTime> onPick;
  static final _fmt = DateFormat('dd MMM yyyy');
  const _DateBtn(
      {required this.date, required this.label, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2024),
          lastDate: DateTime.now().add(const Duration(days: 30)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(primary: _inv)),
            child: child!,
          ),
        );
        if (d != null) onPick(d);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
            color: WakulimaColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: WakulimaColors.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_today_outlined, size: 14, color: _inv),
          const SizedBox(width: 6),
          Text(_fmt.format(date),
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: WakulimaColors.ink)),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded,
            size: 48, color: WakulimaColors.inkMuted),
        const SizedBox(height: 8),
        const Text('Failed to load data',
            style: TextStyle(
                fontFamily: 'Poppins', color: WakulimaColors.inkMuted)),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

// ─── Prominent Search Field ───────────────────────────────────────────────────

class _SearchField extends StatefulWidget {
  final String label, hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? selectedCode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  const _SearchField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    this.selectedCode,
    required this.onChanged,
    this.onClear,
  });
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? _inv : const Color(0xFFDEDEDE),
          width: focused ? 1.8 : 1.2,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                    color: _inv.withOpacity(0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Left icon box
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(8),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: focused ? _inv : const Color(0xFFEDF6F5),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.search_rounded,
              size: 22, color: focused ? Colors.white : _inv),
        ),
        // Text area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label.toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: WakulimaColors.inkMuted,
                        letterSpacing: 0.9)),
                TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: WakulimaColors.ink),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: WakulimaColors.inkMuted,
                        fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.only(top: 2, bottom: 2),
                  ),
                  onChanged: widget.onChanged,
                ),
              ],
            ),
          ),
        ),
        // Right: code badge or clear button
        if (widget.selectedCode != null) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: _inv.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text(widget.selectedCode!,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _inv)),
          ),
          const SizedBox(width: 8),
        ] else if (widget.controller.text.isNotEmpty &&
            widget.onClear != null) ...[
          GestureDetector(
            onTap: widget.onClear,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  size: 16, color: WakulimaColors.inkSoft),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }
}

// ─── Load More Button ─────────────────────────────────────────────────────────

class _LoadMoreBtn extends StatelessWidget {
  final int remaining;
  final VoidCallback onTap;
  const _LoadMoreBtn({required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            border:
                Border(top: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.expand_more_rounded, size: 18, color: _inv),
          const SizedBox(width: 6),
          Text('Load $remaining more',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _inv)),
        ]),
      ),
    );
  }
}
