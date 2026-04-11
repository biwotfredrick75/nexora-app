import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ─── Theme ────────────────────────────────────────────────────────────────────
const _mfg     = WakulimaColors.manufacturing; // Color(0xFF546E7A)
const _mfgDark = Color(0xFF37474F);
const _mfgLight = Color(0xFF78909C);
const _bg      = Color(0xFFF4F6F7); // light blue-grey fill for inputs

// ─── Date Range Helper ────────────────────────────────────────────────────────

class _DateRange {
  final String from, to;
  const _DateRange(this.from, this.to);
  @override
  bool operator ==(Object o) =>
      o is _DateRange && o.from == from && o.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

_DateRange _today() {
  final s = DateFormat('yyyy-MM-dd').format(DateTime.now());
  return _DateRange(s, s);
}

_DateRange _thisWeek() {
  final now  = DateTime.now();
  final mon  = now.subtract(Duration(days: now.weekday - 1));
  final fmt  = DateFormat('yyyy-MM-dd');
  return _DateRange(fmt.format(mon), fmt.format(now));
}

_DateRange _thisMonth() {
  final now = DateTime.now();
  final fmt = DateFormat('yyyy-MM-dd');
  return _DateRange(
    fmt.format(DateTime(now.year, now.month, 1)),
    fmt.format(now),
  );
}

// ─── Providers ────────────────────────────────────────────────────────────────

final _openOrdersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, _DateRange>(
        (ref, range) async {
  try {
    final res = await ref.watch(apiClientProvider).get(
      '/manufacturing/work-orders',
      params: {
        'status': 'open',
        'date_from': range.from,
        'date_to': range.to,
        'per_page': '200',
      },
    ).timeout(const Duration(seconds: 15));
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

final _completedOrdersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, _DateRange>(
        (ref, range) async {
  try {
    final res = await ref.watch(apiClientProvider).get(
      '/manufacturing/work-orders',
      params: {
        'status': 'completed',
        'date_from': range.from,
        'date_to': range.to,
        'per_page': '200',
      },
    ).timeout(const Duration(seconds: 15));
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

final _mfgItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/items', params: {'per_page': '500'})
        .timeout(const Duration(seconds: 15));
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

final _storesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/inventory/stores', params: {'per_page': '200'})
        .timeout(const Duration(seconds: 15));
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

// ─── Main Screen ──────────────────────────────────────────────────────────────

class ManufacturingScreen extends ConsumerStatefulWidget {
  const ManufacturingScreen({super.key});
  @override
  ConsumerState<ManufacturingScreen> createState() =>
      _ManufacturingScreenState();
}

class _ManufacturingScreenState extends ConsumerState<ManufacturingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _mfg,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text('Manufacturing',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 13),
          unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 13),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Open'),
            Tab(text: 'Completed'),
            Tab(text: 'Calculate'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _WorkOrdersTab(status: 'open'),
          _WorkOrdersTab(status: 'completed'),
          _CalculateTab(),
        ],
      ),
      floatingActionButton: _tab.index == 2
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _mfg,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Order',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _ManufactureFormScreen(),
                ),
              ),
            ),
    );
  }
}

// ─── Work Orders Tab ──────────────────────────────────────────────────────────

class _WorkOrdersTab extends ConsumerStatefulWidget {
  final String status;
  const _WorkOrdersTab({required this.status});
  @override
  ConsumerState<_WorkOrdersTab> createState() => _WorkOrdersTabState();
}

class _WorkOrdersTabState extends ConsumerState<_WorkOrdersTab> {
  static final _fmt  = DateFormat('yyyy-MM-dd');
  static final _dlbl = DateFormat('dd MMM');

  int _preset = 0; // 0=Today 1=Week 2=Month 3=Custom
  late _DateRange _range;
  final _presets = ['Today', 'This Week', 'This Month', 'Custom'];

  @override
  void initState() {
    super.initState();
    _range = _today();
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now.add(const Duration(days: 30)),
      initialDateRange: DateTimeRange(
        start: DateTime.tryParse(_range.from) ?? now,
        end: DateTime.tryParse(_range.to) ?? now,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _mfg),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() => _range = _DateRange(
            _fmt.format(range.start),
            _fmt.format(range.end),
          ));
    }
  }

  void _applyPreset(int idx) {
    setState(() {
      _preset = idx;
      switch (idx) {
        case 0:
          _range = _today();
          break;
        case 1:
          _range = _thisWeek();
          break;
        case 2:
          _range = _thisMonth();
          break;
        case 3:
          _pickCustom();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = widget.status == 'open';
    final async  = isOpen
        ? ref.watch(_openOrdersProvider(_range))
        : ref.watch(_completedOrdersProvider(_range));

    return Column(children: [
      // ── Date filter bar ──────────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          // Range label
          Expanded(
            child: Text(
              _range.from == _range.to
                  ? _dlbl.format(DateTime.tryParse(_range.from) ?? DateTime.now())
                  : '${_dlbl.format(DateTime.tryParse(_range.from) ?? DateTime.now())} – ${_dlbl.format(DateTime.tryParse(_range.to) ?? DateTime.now())}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: WakulimaColors.ink),
            ),
          ),
          // Preset dropdown
          GestureDetector(
            onTap: () async {
              final sel = await showModalBottomSheet<int>(
                context: context,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => _PresetSheet(
                    selected: _preset, presets: _presets),
              );
              if (sel != null) _applyPreset(sel);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Text(_presets[_preset],
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _mfg)),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded,
                    size: 16, color: _mfg),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh
          GestureDetector(
            onTap: () => isOpen
                ? ref.invalidate(_openOrdersProvider(_range))
                : ref.invalidate(_completedOrdersProvider(_range)),
            child: const Icon(Icons.refresh_rounded, size: 20, color: _mfgLight),
          ),
        ]),
      ),
      const Divider(height: 1),
      // ── List ────────────────────────────────────────────────────────────
      Expanded(
        child: async.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: _mfg, strokeWidth: 2)),
          error: (_, __) => _ErrorView(
            onRetry: () => isOpen
                ? ref.invalidate(_openOrdersProvider(_range))
                : ref.invalidate(_completedOrdersProvider(_range)),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return _EmptyView(
                icon: Icons.precision_manufacturing_outlined,
                label: 'No ${widget.status} orders',
              );
            }
            return RefreshIndicator(
              color: _mfg,
              onRefresh: () async => isOpen
                  ? ref.invalidate(_openOrdersProvider(_range))
                  : ref.invalidate(_completedOrdersProvider(_range)),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _WorkOrderCard(order: orders[i]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── Work Order Card ──────────────────────────────────────────────────────────

class _WorkOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _WorkOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final ref   = order['reference']?.toString() ?? '—';
    final item  = order['item_name']?.toString() ?? order['item']?.toString() ?? '—';
    final qty   = order['quantity']?.toString() ?? '—';
    final uom   = order['uom']?.toString() ?? '';
    final date  = order['date']?.toString() ?? order['created_at']?.toString() ?? '';
    final status = order['status']?.toString() ?? 'open';

    final isCompleted = status.toLowerCase() == 'completed';
    final statusBg    = isCompleted
        ? const Color(0xFFEAF9EF)
        : const Color(0xFFFEF3CD);
    final statusFg    = isCompleted
        ? const Color(0xFF1A8F33)
        : const Color(0xFF9A6B00);
    final statusLabel = isCompleted ? 'Completed' : 'Open';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _mfg.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Icon(Icons.precision_manufacturing_outlined,
                size: 22, color: _mfg),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(ref,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WakulimaColors.ink)),
            const SizedBox(height: 2),
            Text(item,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: WakulimaColors.inkSoft)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 11, color: WakulimaColors.inkMuted),
              const SizedBox(width: 3),
              Text(date,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: WakulimaColors.inkMuted)),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: statusBg, borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusFg)),
          ),
          const SizedBox(height: 6),
          Text('$qty $uom'.trim(),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _mfg)),
        ]),
      ]),
    );
  }
}

// ─── Calculate Tab ────────────────────────────────────────────────────────────

class _CalculateTab extends ConsumerWidget {
  const _CalculateTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_mfgItemsProvider);

    return Column(children: [
      // Search + Add bar
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                  color: _bg, borderRadius: BorderRadius.circular(20)),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search items…',
                  hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: WakulimaColors.inkMuted),
                  prefixIcon:
                      Icon(Icons.search, size: 18, color: WakulimaColors.inkMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const _ManufactureFormScreen()),
            ),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _mfg, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
      const Divider(height: 1),
      // Items list
      Expanded(
        child: async.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: _mfg, strokeWidth: 2)),
          error: (_, __) => _ErrorView(
              onRetry: () => ref.invalidate(_mfgItemsProvider)),
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyView(
                  icon: Icons.inventory_2_outlined,
                  label: 'No items found');
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _CalcItemTile(item: items[i]),
            );
          },
        ),
      ),
    ]);
  }
}

class _CalcItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _CalcItemTile({required this.item});
  @override
  Widget build(BuildContext context) {
    final name   = item['name']?.toString() ?? item['item_name']?.toString() ?? '—';
    final code   = item['code']?.toString() ?? item['item_code']?.toString() ?? '';
    final hasBom = item['has_bom'] == true || item['bom_count'] != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: _mfg.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)),
          child:
              const Center(child: Icon(Icons.widgets_outlined, size: 20, color: _mfg)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WakulimaColors.ink)),
            if (code.isNotEmpty)
              Text(code,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: WakulimaColors.inkMuted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: hasBom
                ? const Color(0xFFEAF9EF)
                : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            hasBom ? 'Has BOM' : 'No BOM',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hasBom
                    ? const Color(0xFF1A8F33)
                    : WakulimaColors.inkMuted),
          ),
        ),
      ]),
    );
  }
}

// ─── Manufacture Form Screen ──────────────────────────────────────────────────

class _ManufactureFormScreen extends ConsumerStatefulWidget {
  const _ManufactureFormScreen();
  @override
  ConsumerState<_ManufactureFormScreen> createState() =>
      _ManufactureFormScreenState();
}

class _ManufactureFormScreenState
    extends ConsumerState<_ManufactureFormScreen> {
  final _qtyCtrl     = TextEditingController();
  final _labourCtrl  = TextEditingController();
  final _overheadCtrl = TextEditingController();

  String? _action;  // Assemble / Disassemble / Process
  Map<String, dynamic>? _item;
  Map<String, dynamic>? _destination;
  bool _costPerItem = false;
  bool _saving = false;

  final _errors = <String, String>{};

  bool _validate() {
    _errors.clear();
    if (_action == null) _errors['action'] = 'Select an action';
    if (_item == null) _errors['item'] = 'Select an item';
    if (_qtyCtrl.text.trim().isEmpty) _errors['qty'] = 'Enter quantity';
    if (_destination == null) _errors['destination'] = 'Select destination';
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'action'     : _action,
        'item_id'    : _item!['id'],
        'quantity'   : double.tryParse(_qtyCtrl.text.trim()) ?? 0,
        'destination': _destination!['id'],
        'labour_cost'  : double.tryParse(_labourCtrl.text.trim()) ?? 0,
        'overhead_cost': double.tryParse(_overheadCtrl.text.trim()) ?? 0,
        'cost_mode'  : _costPerItem ? 'per_item' : 'total',
      };
      await ref
          .read(apiClientProvider)
          .post('/manufacturing/work-orders', data: payload)
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Work order created',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: _mfg,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      String msg = 'Failed to save. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _labourCtrl.dispose();
    _overheadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items  = ref.watch(_mfgItemsProvider).valueOrNull ?? [];
    final stores = ref.watch(_storesProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _mfg,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New Work Order',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // ── Manufacturing Details ───────────────────────────────────────
          _FormCard(
            title: 'Manufacturing Details',
            icon: Icons.build_outlined,
            children: [
              _DropdownField(
                label: 'Action',
                hint: 'Select action…',
                value: _action,
                items: const ['Assemble', 'Disassemble', 'Process'],
                error: _errors['action'],
                onChanged: (v) => setState(() {
                  _action = v;
                  _errors.remove('action');
                }),
              ),
              const SizedBox(height: 12),
              _PickerField(
                label: 'Item',
                hint: 'Select item…',
                value: _item == null
                    ? null
                    : (_item!['name']?.toString() ??
                        _item!['item_name']?.toString() ??
                        ''),
                error: _errors['item'],
                onTap: () async {
                  final sel = await _SearchSheet.show<Map<String, dynamic>>(
                    context: context,
                    title: 'Select Item',
                    items: items,
                    label: (e) =>
                        e['name']?.toString() ??
                        e['item_name']?.toString() ??
                        '',
                    sub: (e) => e['code']?.toString() ?? '',
                  );
                  if (sel != null) {
                    setState(() {
                      _item = sel;
                      _errors.remove('item');
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              _NumInput(
                label: 'Quantity',
                ctrl: _qtyCtrl,
                error: _errors['qty'],
                onChanged: (_) => setState(() => _errors.remove('qty')),
              ),
              const SizedBox(height: 12),
              _PickerField(
                label: 'Destination Store',
                hint: 'Select store…',
                value: _destination == null
                    ? null
                    : (_destination!['name']?.toString() ?? ''),
                error: _errors['destination'],
                onTap: () async {
                  final sel = await _SearchSheet.show<Map<String, dynamic>>(
                    context: context,
                    title: 'Select Store',
                    items: stores,
                    label: (e) => e['name']?.toString() ?? '',
                    sub: (e) => e['code']?.toString() ?? '',
                  );
                  if (sel != null) {
                    setState(() {
                      _destination = sel;
                      _errors.remove('destination');
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Cost Calculation ────────────────────────────────────────────
          _FormCard(
            title: 'Cost Calculation',
            icon: Icons.calculate_outlined,
            children: [
              // Toggle: Total Cost / Cost Per Item
              Row(children: [
                _CostToggleBtn(
                  label: 'Total Cost',
                  selected: !_costPerItem,
                  onTap: () => setState(() => _costPerItem = false),
                ),
                const SizedBox(width: 8),
                _CostToggleBtn(
                  label: 'Cost Per Item',
                  selected: _costPerItem,
                  onTap: () => setState(() => _costPerItem = true),
                ),
              ]),
              const SizedBox(height: 16),
              // Labour
              const _SectionLabel('Labour Costs'),
              const SizedBox(height: 8),
              _NumInput(
                label: _costPerItem ? 'Labour Cost Per Item' : 'Total Labour Cost',
                ctrl: _labourCtrl,
              ),
              const SizedBox(height: 12),
              // Overhead
              const _SectionLabel('Overhead Costs'),
              const SizedBox(height: 8),
              _NumInput(
                label: _costPerItem
                    ? 'Overhead Cost Per Item'
                    : 'Total Overhead Cost',
                ctrl: _overheadCtrl,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Save Button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _mfg,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Work Order',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

// ─── Form Card ────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _FormCard(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14)),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: _mfg),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _mfgDark)),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ]),
    );
  }
}

// ─── Field Widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _mfgLight));
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: WakulimaColors.inkSoft)),
      );
}

class _DropdownField extends StatelessWidget {
  final String label, hint;
  final String? value, error;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _DropdownField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(label),
      SizedBox(
        height: 42,
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            filled: true,
            fillColor: _bg,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: error != null
                        ? Colors.red
                        : WakulimaColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: error != null
                        ? Colors.red
                        : WakulimaColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _mfg)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red)),
          ),
          hint: Text(hint,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMuted)),
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: WakulimaColors.ink),
          items: items
              .map((e) =>
                  DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(error!,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.red)),
        ),
    ]);
  }
}

class _PickerField extends StatelessWidget {
  final String label, hint;
  final String? value, error;
  final VoidCallback onTap;
  const _PickerField({
    required this.label,
    required this.hint,
    required this.onTap,
    this.value,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(label),
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color:
                    error != null ? Colors.red : WakulimaColors.border),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: value != null
                        ? WakulimaColors.ink
                        : WakulimaColors.inkMuted),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: WakulimaColors.inkMuted),
          ]),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(error!,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.red)),
        ),
    ]);
  }
}

class _NumInput extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? error;
  final ValueChanged<String>? onChanged;
  const _NumInput(
      {required this.label, required this.ctrl, this.error, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(label),
      SizedBox(
        height: 42,
        child: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: _bg,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: error != null
                        ? Colors.red
                        : WakulimaColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: error != null
                        ? Colors.red
                        : WakulimaColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _mfg)),
            hintText: '0.00',
            hintStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: WakulimaColors.inkMuted),
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(error!,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.red)),
        ),
    ]);
  }
}

class _CostToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CostToggleBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _mfg : _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _mfg : WakulimaColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _mfgLight)),
      ),
    );
  }
}

// ─── Preset Sheet ─────────────────────────────────────────────────────────────

class _PresetSheet extends StatelessWidget {
  final int selected;
  final List<String> presets;
  const _PresetSheet({required this.selected, required this.presets});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: WakulimaColors.border,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Date Range',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: WakulimaColors.ink)),
          ),
        ),
        const Divider(height: 1),
        ...List.generate(
          presets.length,
          (i) => ListTile(
            title: Text(presets[i],
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: selected == i
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selected == i ? _mfg : WakulimaColors.ink)),
            trailing: selected == i
                ? const Icon(Icons.check_rounded, color: _mfg)
                : null,
            onTap: () => Navigator.of(context).pop(i),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ─── Search Sheet ─────────────────────────────────────────────────────────────

class _SearchSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T) label,
    String Function(T)? sub,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) =>
          _SearchSheetContent<T>(title: title, items: items, label: label, sub: sub),
    );
  }
}

class _SearchSheetContent<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) label;
  final String Function(T)? sub;
  const _SearchSheetContent(
      {required this.title,
      required this.items,
      required this.label,
      this.sub});

  @override
  State<_SearchSheetContent<T>> createState() =>
      _SearchSheetContentState<T>();
}

class _SearchSheetContentState<T> extends State<_SearchSheetContent<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.items
        : widget.items
            .where((e) =>
                widget.label(e).toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(children: [
        const SizedBox(height: 12),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: WakulimaColors.border,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Text(widget.title,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: WakulimaColors.ink)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search…',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins', color: WakulimaColors.inkMuted),
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: _bg,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: ctrl,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final e    = filtered[i];
              final lbl  = widget.label(e);
              final s    = widget.sub?.call(e) ?? '';
              return ListTile(
                title: Text(lbl,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                subtitle: s.isNotEmpty
                    ? Text(s,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: WakulimaColors.inkMuted))
                    : null,
                onTap: () => Navigator.of(context).pop(e),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Reusable ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyView({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: _mfg.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: WakulimaColors.inkMuted)),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded,
              size: 48, color: WakulimaColors.inkMuted),
          const SizedBox(height: 8),
          const Text('Failed to load data',
              style: TextStyle(
                  fontFamily: 'Poppins', color: WakulimaColors.inkMuted)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry',
                style: TextStyle(color: _mfg, fontFamily: 'Poppins')),
          ),
        ]),
      );
}
