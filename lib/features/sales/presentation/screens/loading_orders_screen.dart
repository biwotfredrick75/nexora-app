import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

const _primary = WakulimaColors.primary700;

// ─── Provider: fetch full items for each delivery ─────────────────────────────

final _loadingOrdersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, vehicle) async {
  // Called with vehicle as key; actual loading is handled by the widget
  // which passes deliveries as extra. This provider fetches full items.
  return [];
});

final _deliveryDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
        (ref, id) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/sales/deliveries/$id')
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] == true) return Map<String, dynamic>.from(b['data'] as Map);
  } catch (_) {}
  return {};
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class LoadingOrdersScreen extends ConsumerStatefulWidget {
  final String vehicle;
  final String date;
  final List<Map<String, dynamic>> deliveries;

  const LoadingOrdersScreen({
    super.key,
    required this.vehicle,
    required this.date,
    required this.deliveries,
  });

  @override
  ConsumerState<LoadingOrdersScreen> createState() =>
      _LoadingOrdersScreenState();
}

class _LoadingOrdersScreenState extends ConsumerState<LoadingOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _dispatching = false;

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

  // Fetch all delivery details (with items)
  List<int> get _ids =>
      widget.deliveries.map((d) => (d['id'] as num).toInt()).toList();

  Future<void> _dispatch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Dispatch',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Dispatch ${widget.deliveries.length} order(s) for vehicle ${widget.vehicle}?',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white),
            child: const Text('Dispatch',
                style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _dispatching = true);
    int success = 0;
    final api = ref.read(apiClientProvider);
    for (final id in _ids) {
      try {
        final res = await api
            .post('/sales/deliveries/$id/place', data: {})
            .timeout(const Duration(seconds: 10));
        final b = res.data as Map<String, dynamic>;
        if (b['success'] == true) success++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _dispatching = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            success == _ids.length
                ? 'Dispatched ${widget.vehicle} successfully'
                : '$success/${_ids.length} orders dispatched',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: success > 0 ? _primary : WakulimaColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (mounted && success > 0) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Watch all delivery details
    final detailsAsync = _ids
        .map((id) => ref.watch(_deliveryDetailProvider(id)))
        .toList();

    final allLoaded = detailsAsync.every((a) => a.hasValue);
    final details = allLoaded
        ? detailsAsync.map((a) => a.value ?? {}).toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text('Loading Orders for ${widget.vehicle}',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w400),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Per Customer'),
          ],
        ),
      ),
      body: allLoaded
          ? TabBarView(
              controller: _tabs,
              children: [
                _SummaryTab(details: details),
                _PerCustomerTab(details: details),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                  color: _primary, strokeWidth: 2)),
      floatingActionButton: _dispatching
          ? const FloatingActionButton.extended(
              onPressed: null,
              label: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
              icon: null,
              backgroundColor: _primary,
            )
          : FloatingActionButton.extended(
              onPressed: _dispatch,
              backgroundColor: _primary,
              icon: const Icon(Icons.local_shipping_outlined,
                  color: Colors.white),
              label: const Text('Dispatch',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
    );
  }
}

// ─── Summary Tab ──────────────────────────────────────────────────────────────

class _SummaryTab extends StatelessWidget {
  final List<Map<String, dynamic>> details;
  const _SummaryTab({required this.details});

  @override
  Widget build(BuildContext context) {
    // Aggregate items by stock_id
    final Map<String, _SummaryItem> agg = {};
    for (final d in details) {
      final items = d['items'] as List? ?? [];
      for (final it in items) {
        final sid  = it['stock_id']?.toString() ?? '';
        final desc = it['description']?.toString() ?? sid;
        final qty  = (it['qty'] as num?)?.toDouble() ?? 0;
        if (agg.containsKey(sid)) {
          agg[sid] = _SummaryItem(sid, desc, agg[sid]!.qty + qty);
        } else {
          agg[sid] = _SummaryItem(sid, desc, qty);
        }
      }
    }
    final rows = agg.values.toList();

    return Column(children: [
      // Header row
      Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          const Text('Items',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: WakulimaColors.inkMuted)),
          const Spacer(),
          Text('Item Count: ${rows.length}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: WakulimaColors.inkMuted)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: rows.isEmpty
            ? const Center(
                child: Text('No items',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: WakulimaColors.inkMuted)))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Expanded(
                        child: Text(r.description,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: WakulimaColors.ink)),
                      ),
                      Text('Qty: ${_fmtQty(r.qty)}',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: WakulimaColors.ink)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
}

// ─── Per Customer Tab ─────────────────────────────────────────────────────────

class _PerCustomerTab extends StatelessWidget {
  final List<Map<String, dynamic>> details;
  const _PerCustomerTab({required this.details});

  @override
  Widget build(BuildContext context) {
    // Group items by customer (preserve delivery order)
    final Map<String, List<_CustomerItem>> grouped = {};
    for (final d in details) {
      final customer = d['customer'] is Map
          ? (d['customer']['name']?.toString() ?? d['debtor_no']?.toString() ?? '—')
          : (d['debtor_no']?.toString() ?? '—');
      final deliverTo = d['deliver_to']?.toString() ?? '';
      final displayName =
          deliverTo.isNotEmpty ? '$customer  $deliverTo' : customer;
      final items = d['items'] as List? ?? [];
      for (final it in items) {
        grouped.putIfAbsent(displayName, () => []).add(_CustomerItem(
          customer: displayName,
          item: it['description']?.toString() ??
              it['stock_id']?.toString() ??
              '—',
          qty: (it['qty'] as num?)?.toDouble() ?? 0,
        ));
      }
    }

    final customers = grouped.keys.toList();
    final total = details.length;

    // Build a flat scroll list: customer header + its product rows
    // We use a sliver-style index map
    final List<_ScrollEntry> entries = [];
    for (final c in customers) {
      entries.add(_ScrollEntry(isHeader: true, customer: c, item: null));
      for (final it in grouped[c]!) {
        entries.add(_ScrollEntry(isHeader: false, customer: c, item: it));
      }
    }

    return Column(children: [
      // Header bar
      Container(
        color: const Color(0xFFF5F5F5),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          const Text('Loading Orders',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: WakulimaColors.inkMuted)),
          const Spacer(),
          Text('Total: $total',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: WakulimaColors.inkMuted)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: entries.isEmpty
            ? const Center(
                child: Text('No orders',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: WakulimaColors.inkMuted)))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final e = entries[i];
                  if (e.isHeader) {
                    // ── Customer header ──────────────────────────────
                    return Container(
                      color: const Color(0xFFF8F8F8),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: _primary.withOpacity(0.12),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.store_outlined,
                              size: 14, color: _primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(e.customer,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: WakulimaColors.ink)),
                        ),
                      ]),
                    );
                  }
                  // ── Product row ──────────────────────────────────
                  final it = e.item!;
                  final isLast = i == entries.length - 1 ||
                      entries[i + 1].isHeader;
                  return Container(
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: isLast
                                    ? const Color(0xFFE0E0E0)
                                    : const Color(0xFFF0F0F0)))),
                    padding: const EdgeInsets.fromLTRB(54, 8, 16, 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(it.item,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: WakulimaColors.inkSoft)),
                      ),
                      const SizedBox(width: 12),
                      Text('Qty ${_fmtQty(it.qty)}',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: WakulimaColors.ink)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
}

class _ScrollEntry {
  final bool isHeader;
  final String customer;
  final _CustomerItem? item;
  const _ScrollEntry(
      {required this.isHeader, required this.customer, this.item});
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _SummaryItem {
  final String stockId, description;
  final double qty;
  const _SummaryItem(this.stockId, this.description, this.qty);
}

class _CustomerItem {
  final String customer, item;
  final double qty;
  const _CustomerItem(
      {required this.customer, required this.item, required this.qty});
}
