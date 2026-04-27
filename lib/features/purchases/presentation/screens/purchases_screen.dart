import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/sales/data/sales_form_shared.dart';

const _indigo = WakulimaColors.purchases;
const _indigoBright = Color(0xFF3949AB);
final _dateFmt = DateFormat('yyyy-MM-dd');

// ─── Providers ────────────────────────────────────────────────────────────────

final _purchasesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/purchases', params: {'per_page': '100'})
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    return _toMapList(raw is Map ? raw['data'] ?? [] : raw ?? []);
  } catch (_) {
    return [];
  }
});

final _grnProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/purchases/grn', params: {'per_page': '100'})
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    return _toMapList(raw is Map ? raw['data'] ?? [] : raw ?? []);
  } catch (_) {
    return [];
  }
});

final _purchaseSuppliersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/purchases/suppliers', params: {'per_page': '200'})
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    return _toMapList(raw is Map ? raw['data'] ?? [] : raw ?? []);
  } catch (_) {
    return [];
  }
});

List<Map<String, dynamic>> _toMapList(dynamic src) {
  if (src is! List) return [];
  return src
      .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

List<Map<String, dynamic>> _filterList(
    List<Map<String, dynamic>> all, String search, DateTime? date) {
  return all.where((item) {
    if (search.isNotEmpty) {
      final text = [
        item['reference'],
        item['supplier_name'],
        item['grn_no'],
        item['id']?.toString(),
        if (item['supplier'] is Map) item['supplier']['name'],
      ].whereType<String>().join(' ').toLowerCase();
      if (!text.contains(search.toLowerCase())) return false;
    }
    if (date != null) {
      final d =
          item['date']?.toString() ?? item['created_at']?.toString() ?? '';
      if (!d.startsWith(_dateFmt.format(date))) return false;
    }
    return true;
  }).toList();
}

Future<DateTime?> _pickDate(BuildContext context, DateTime? current) =>
    showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _indigo)),
        child: child!,
      ),
    );

// ─── Main Screen ──────────────────────────────────────────────────────────────

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text('Purchases',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(_purchasesProvider);
              ref.invalidate(_grnProvider);
              ref.invalidate(_purchaseSuppliersProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w400),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(
                icon: Icon(Icons.receipt_long_outlined, size: 16),
                text: 'Purchase'),
            Tab(
                icon: Icon(Icons.local_shipping_outlined, size: 16),
                text: 'Maize GRN'),
            Tab(
                icon: Icon(Icons.people_outline_rounded, size: 16),
                text: 'Suppliers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _PurchaseTab(),
          _GrnTab(),
          _SuppliersTab(),
        ],
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  Widget? _buildFab(BuildContext context) {
    if (_tabs.index == 0) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.extended(
          heroTag: 'fab_grn',
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _AddGrnScreen())),
          backgroundColor: _indigoBright,
          icon: const Icon(Icons.local_shipping_outlined, color: Colors.white),
          label: const Text('Add GRN',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab_purchase',
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _AddPurchaseScreen())),
          backgroundColor: _indigo,
          icon: const Icon(Icons.add_shopping_cart_outlined,
              color: Colors.white),
          label: const Text('Add Purchase',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      ]);
    }
    if (_tabs.index == 1) {
      return FloatingActionButton.extended(
        heroTag: 'fab_grn2',
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _AddGrnScreen())),
        backgroundColor: _indigoBright,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add GRN',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );
    }
    if (_tabs.index == 2) {
      return FloatingActionButton.extended(
        heroTag: 'fab_supplier',
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const _CreateSupplierScreen())),
        backgroundColor: _indigo,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Add Supplier',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );
    }
    return null;
  }
}

// ─── Purchase Tab ─────────────────────────────────────────────────────────────

class _PurchaseTab extends ConsumerStatefulWidget {
  const _PurchaseTab();

  @override
  ConsumerState<_PurchaseTab> createState() => _PurchaseTabState();
}

class _PurchaseTabState extends ConsumerState<_PurchaseTab> {
  String _search = '';
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_purchasesProvider);
    return Column(children: [
      _SearchBar(
        onSearch: (v) => setState(() => _search = v),
        onDateTap: () async {
          final d = await _pickDate(context, _date);
          if (d != null) setState(() => _date = d);
        },
        hasFilter: _date != null,
        onClear: () => setState(() => _date = null),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: _indigo, strokeWidth: 2)),
          error: (_, __) =>
              _ErrorView(onRetry: () => ref.invalidate(_purchasesProvider)),
          data: (all) {
            final items = _filterList(all, _search, _date);
            if (items.isEmpty) {
              return _EmptyView(
                icon: Icons.receipt_long_outlined,
                message: 'No Available purchases.\nPull down to refresh',
                onRefresh: () => ref.invalidate(_purchasesProvider),
              );
            }
            return RefreshIndicator(
              color: _indigo,
              onRefresh: () async => ref.invalidate(_purchasesProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _PurchaseCard(item: items[i]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── GRN Tab ──────────────────────────────────────────────────────────────────

class _GrnTab extends ConsumerStatefulWidget {
  const _GrnTab();

  @override
  ConsumerState<_GrnTab> createState() => _GrnTabState();
}

class _GrnTabState extends ConsumerState<_GrnTab> {
  String _search = '';
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_grnProvider);
    return Column(children: [
      _SearchBar(
        onSearch: (v) => setState(() => _search = v),
        onDateTap: () async {
          final d = await _pickDate(context, _date);
          if (d != null) setState(() => _date = d);
        },
        hasFilter: _date != null,
        onClear: () => setState(() => _date = null),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: _indigo, strokeWidth: 2)),
          error: (_, __) =>
              _ErrorView(onRetry: () => ref.invalidate(_grnProvider)),
          data: (all) {
            final items = _filterList(all, _search, _date);
            if (items.isEmpty) {
              return _EmptyView(
                icon: Icons.local_shipping_outlined,
                message: 'No GRN records.\nPull down to refresh',
                onRefresh: () => ref.invalidate(_grnProvider),
              );
            }
            return RefreshIndicator(
              color: _indigo,
              onRefresh: () async => ref.invalidate(_grnProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _GrnCard(item: items[i]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── Suppliers Tab ────────────────────────────────────────────────────────────

class _SuppliersTab extends ConsumerStatefulWidget {
  const _SuppliersTab();

  @override
  ConsumerState<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends ConsumerState<_SuppliersTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_purchaseSuppliersProvider);
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WakulimaColors.border)),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Search suppliers…',
              hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMuted),
              prefixIcon: Icon(Icons.search,
                  size: 18, color: WakulimaColors.inkMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      const Divider(height: 1),
      Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(children: [
          Text('Added Suppliers',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _indigo)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: async.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: _indigo, strokeWidth: 2)),
          error: (_, __) => _ErrorView(
              onRetry: () => ref.invalidate(_purchaseSuppliersProvider)),
          data: (all) {
            final items = _search.isEmpty
                ? all
                : all
                    .where((s) => (s['supplierName'] ?? s['supplierName'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(_search.toLowerCase()))
                    .toList();
            if (items.isEmpty) {
              return _EmptyView(
                icon: Icons.people_outline_rounded,
                message: 'No suppliers added yet',
                onRefresh: () =>
                    ref.invalidate(_purchaseSuppliersProvider),
              );
            }
            return RefreshIndicator(
              color: _indigo,
              onRefresh: () async =>
                  ref.invalidate(_purchaseSuppliersProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _SupplierCard(supplier: items[i]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── Cards ────────────────────────────────────────────────────────────────────

class _PurchaseCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _PurchaseCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final ref = item['reference']?.toString() ??
        item['id']?.toString() ?? '—';
    final supplier = item['supplier_name']?.toString() ??
        (item['supplier'] is Map
            ? item['supplier']['name']?.toString()
            : null) ??
        '—';
    final date =
        item['date']?.toString() ?? item['created_at']?.toString() ?? '';
    final total = (item['total'] as num?)?.toDouble() ?? 0;
    final status = item['status']?.toString() ?? 'draft';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: _indigo.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.receipt_long_outlined,
              size: 20, color: _indigo),
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
            Text(supplier,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: WakulimaColors.inkSoft)),
            if (date.isNotEmpty)
              Text(date.substring(0, date.length.clamp(0, 10)),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: WakulimaColors.inkMuted)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('KES ${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _indigo)),
          const SizedBox(height: 4),
          _StatusBadge(status),
        ]),
      ]),
    );
  }
}

class _GrnCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _GrnCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final grn = item['grn_no']?.toString() ??
        item['reference']?.toString() ??
        item['id']?.toString() ?? '—';
    final supplier = item['supplier_name']?.toString() ??
        (item['supplier'] is Map
            ? item['supplier']['name']?.toString()
            : null) ??
        '—';
    final date =
        item['date']?.toString() ?? item['created_at']?.toString() ?? '';
    final totalKg = (item['total_kg'] as num?)?.toDouble() ??
        (item['total_weight'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: _indigoBright.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.local_shipping_outlined,
              size: 20, color: _indigoBright),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(grn,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WakulimaColors.ink)),
            const SizedBox(height: 2),
            Text(supplier,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: WakulimaColors.inkSoft)),
            if (date.isNotEmpty)
              Text(date.substring(0, date.length.clamp(0, 10)),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: WakulimaColors.inkMuted)),
          ]),
        ),
        Text('${totalKg.toStringAsFixed(1)} KG',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _indigoBright)),
      ]),
    );
  }
}

String _supplierName(Map<String, dynamic> s) {
  for (final k in ['name', 'supplierName', 'full_name', 'company_name', 'title', 'short_name']) {
    final v = s[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return '—';
}

class _SupplierCard extends StatelessWidget {
  final Map<String, dynamic> supplier;
  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final name = _supplierName(supplier);
    final phone = supplier['memberNumber']?.toString() ??
        supplier['phone_number']?.toString() ??
        supplier['mobile']?.toString() ?? '';
    final code = supplier['code']?.toString() ??
        supplier['supplierId']?.toString() ??
        supplier['supplierName']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: _indigo.withOpacity(0.1),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: _indigo,
                fontSize: 16),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(name,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WakulimaColors.ink)),
            if (phone.isNotEmpty)
              Text(phone,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: WakulimaColors.inkSoft)),
          ]),
        ),
        if (code.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _indigo.withOpacity(0.07),
                borderRadius: BorderRadius.circular(6)),
            child: Text(code,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _indigo)),
          ),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status.toLowerCase()) {
      case 'approved':
        bg = const Color(0xFFEAF9EF);
        fg = const Color(0xFF1A8F33);
        break;
      case 'pending':
        bg = const Color(0xFFFEF3CD);
        fg = const Color(0xFF9A6B00);
        break;
      case 'draft':
        bg = const Color(0xFFF0F0F0);
        fg = WakulimaColors.inkSoft;
        break;
      default:
        bg = const Color(0xFFE8F4FD);
        fg = const Color(0xFF1565C0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onSearch;
  final VoidCallback onDateTap;
  final bool hasFilter;
  final VoidCallback onClear;
  const _SearchBar({
    required this.onSearch,
    required this.onDateTap,
    required this.hasFilter,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WakulimaColors.border)),
              child: TextField(
                onChanged: onSearch,
                style:
                    const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: WakulimaColors.inkMuted),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: WakulimaColors.inkMuted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onDateTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                  color: hasFilter
                      ? _indigo.withOpacity(0.1)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: hasFilter ? _indigo : WakulimaColors.border)),
              child: Icon(Icons.calendar_today_outlined,
                  size: 18,
                  color:
                      hasFilter ? _indigo : WakulimaColors.inkSoft),
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close,
                  size: 18, color: WakulimaColors.inkMuted),
            ),
          ],
        ]),
      ),
      const Divider(height: 1),
    ]);
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onRefresh;
  const _EmptyView(
      {required this.icon,
      required this.message,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _indigo,
      onRefresh: () async => onRefresh(),
      child: ListView(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 64, color: _indigo.withOpacity(0.15)),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: WakulimaColors.inkMuted)),
          ]),
        ),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded,
            size: 48, color: WakulimaColors.inkMuted),
        const SizedBox(height: 8),
        const Text('Failed to load',
            style: TextStyle(
                fontFamily: 'Poppins', color: WakulimaColors.inkMuted)),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

// ─── Add GRN Screen ───────────────────────────────────────────────────────────

class _GrnCartItem {
  String itemId;
  String description;
  double pricePerKg;
  double weightKg;
  String uom;
  _GrnCartItem(
      {required this.itemId,
      required this.description,
      this.pricePerKg = 0,
      this.weightKg = 0,
      this.uom = 'KG'});
  double get total => pricePerKg * weightKg;
}

class _AddGrnScreen extends ConsumerStatefulWidget {
  const _AddGrnScreen();

  @override
  ConsumerState<_AddGrnScreen> createState() => _AddGrnScreenState();
}

class _AddGrnScreenState extends ConsumerState<_AddGrnScreen> {
  String? _supplierId;
  String? _supplierLabel;
  DateTime _date = DateTime.now();
  String? _storeId;
  String? _storeLabel;
  String? _itemId;
  String? _itemLabel;
  String _itemUom = 'KG';
  final _priceCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  bool _useScale = true;
  final List<_GrnCartItem> _cart = [];
  bool _saving = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _addToCart() {
    if (_itemId == null) { _snack('Select an item'); return; }
    final weight = double.tryParse(_weightCtrl.text) ?? 0;
    if (weight <= 0) { _snack('Enter a valid weight'); return; }
    setState(() {
      _cart.add(_GrnCartItem(
        itemId: _itemId!,
        description: _itemLabel ?? _itemId!,
        pricePerKg: double.tryParse(_priceCtrl.text) ?? 0,
        weightKg: weight,
        uom: _itemUom,
      ));
      _itemId = null;
      _itemLabel = null;
      _priceCtrl.clear();
      _weightCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (_supplierId == null) { _snack('Select a supplier'); return; }
    if (_cart.isEmpty) { _snack('Add at least one item'); return; }
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/purchases/grn', data: {
        'supplier_id': _supplierId,
        'date': _dateFmt.format(_date),
        if (_storeId != null) 'store_id': _storeId,
        'items': _cart.map((i) => {
              'item_id': i.itemId,
              'price_per_kg': i.pricePerKg,
              'weight_kg': i.weightKg,
              'uom': i.uom,
            }).toList(),
      }).timeout(const Duration(seconds: 15));
      final b = res.data as Map<String, dynamic>;
      if (b['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('GRN saved successfully',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Color(0xFF1A8F33),
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.of(context).pop();
        }
      } else {
        _snack(b['message']?.toString() ?? 'Failed');
      }
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: WakulimaColors.error,
            behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(_purchaseSuppliersProvider).maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final locations = ref.watch(sfLocationsProvider).maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final items = ref.watch(sfStockItemsProvider).maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar('Add GRN Entry', _indigoBright),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Basic Information ────────────────────────────────────────────
          _SectionLabel('Basic Information'),
          const SizedBox(height: 12),
          _Label('Supplier'),
          _Picker(
              value: _supplierLabel,
              hint: 'Select supplier',
              onTap: () => _sheet(context, 'Select Supplier', suppliers,
                  'supplierName', 'supplierId', (id, lbl) {
                setState(() { _supplierId = id; _supplierLabel = lbl; });
              }, fallbackKeys: ['supplier_name', 'full_name', 'company_name', 'title'])),
          const SizedBox(height: 14),
          _Label('Date'),
          _DatePicker(value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 14),
          _Label('Destination Store'),
          _Picker(
              value: _storeLabel,
              hint: 'Select store',
              onTap: () => _sheet(context, 'Select Store', locations,
                  'name', 'code', (id, lbl) {
                setState(() { _storeId = id; _storeLabel = lbl; });
              })),
          const SizedBox(height: 24),

          // ── Item Entry ───────────────────────────────────────────────────
          _SectionLabel('Item Entry'),
          const SizedBox(height: 12),
          _Label('Item'),
          _Picker(
              value: _itemLabel,
              hint: 'Select item',
              onTap: () => _sheet(context, 'Select Item', items,
                  'description', 'stock_id', (id, lbl) {
                final it = items.firstWhere(
                    (i) => i['stock_id']?.toString() == id,
                    orElse: () => {});
                setState(() {
                  _itemId = id;
                  _itemLabel = lbl;
                  _itemUom = it['unit']?.toString() ?? 'KG';
                });
              })),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: _Label('Price per KG')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _indigoBright.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('UOM: $_itemUom',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _indigoBright)),
            ),
          ]),
          const SizedBox(height: 6),
          _NumField(controller: _priceCtrl, hint: '0.00'),
          const SizedBox(height: 20),

          // ── Weight Collection ────────────────────────────────────────────
          _SectionLabel('Weight Collection'),
          const SizedBox(height: 12),
          Row(children: [
            _ToggleChip(
                label: 'Use Weigh Device',
                selected: _useScale,
                color: _indigo,
                onTap: () => setState(() => _useScale = true)),
            const SizedBox(width: 10),
            _ToggleChip(
                label: 'Manual Input',
                selected: !_useScale,
                color: _indigo,
                onTap: () => setState(() => _useScale = false)),
          ]),
          const SizedBox(height: 14),
          if (_useScale)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WakulimaColors.border)),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: Color(0xFF43A047),
                        shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('Ready',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Color(0xFF43A047))),
                const SizedBox(width: 10),
                Text(
                    '${double.tryParse(_weightCtrl.text)?.toStringAsFixed(1) ?? '0.0'} KG',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF43A047))),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10)),
                  child: const Text('Connect Scale',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ]),
            )
          else ...[
            _Label('Weight (KG)'),
            const SizedBox(height: 6),
            _NumField(controller: _weightCtrl, hint: '0.0'),
          ],
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addToCart,
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: const Text('Add Item to Cart',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _indigo,
                  side: const BorderSide(color: _indigo),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
          const SizedBox(height: 24),

          // ── Cart ─────────────────────────────────────────────────────────
          Row(children: [
            const Text('Cart Items',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WakulimaColors.ink)),
            const Spacer(),
            if (_cart.isNotEmpty)
              Text('${_cart.length} item${_cart.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: WakulimaColors.inkMuted)),
          ]),
          const SizedBox(height: 8),
          _CartTable(
            headers: const ['Item', 'Price/KG', 'Qty'],
            rows: _cart.map((i) => [
                  i.description,
                  i.pricePerKg.toStringAsFixed(2),
                  '${i.weightKg.toStringAsFixed(1)} ${i.uom}',
                ]).toList(),
            emptyMsg:
                'No items added yet.\nAdd items using the form above.',
            onRemove: (i) => setState(() => _cart.removeAt(i)),
            footer: _cart.isEmpty
                ? null
                : Row(children: [
                    const Text('Total KG',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: WakulimaColors.ink)),
                    const Spacer(),
                    Text(
                        '${_cart.fold<double>(0, (s, i) => s + i.weightKg).toStringAsFixed(1)} KG',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _indigoBright)),
                  ]),
          ),
          const SizedBox(height: 24),

          _SaveBtn(
            label:
                'Save GRN (${_cart.length} item${_cart.length == 1 ? '' : 's'})',
            saving: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Add Purchase Screen ──────────────────────────────────────────────────────

class _PurchaseLine {
  String itemId;
  String description;
  double price;
  double qty;
  String uom;
  _PurchaseLine(
      {required this.itemId,
      required this.description,
      this.price = 0,
      this.qty = 0,
      this.uom = 'PCS'});
  double get total => price * qty;
}

class _AddPurchaseScreen extends ConsumerStatefulWidget {
  const _AddPurchaseScreen();

  @override
  ConsumerState<_AddPurchaseScreen> createState() =>
      _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends ConsumerState<_AddPurchaseScreen> {
  String? _supplierId, _supplierLabel;
  DateTime _date = DateTime.now();
  String? _destId, _destLabel;
  String? _itemId, _itemLabel;
  String _itemUom = 'PCS';
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final List<_PurchaseLine> _lines = [];
  bool _saving = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _addLine() {
    if (_itemId == null) { _snack('Select an item'); return; }
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) { _snack('Enter a valid quantity'); return; }
    setState(() {
      _lines.add(_PurchaseLine(
        itemId: _itemId!,
        description: _itemLabel ?? _itemId!,
        price: double.tryParse(_priceCtrl.text) ?? 0,
        qty: qty,
        uom: _itemUom,
      ));
      _itemId = null; _itemLabel = null;
      _priceCtrl.clear(); _qtyCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (_supplierId == null) { _snack('Select a supplier'); return; }
    if (_lines.isEmpty) { _snack('Add at least one item'); return; }
    setState(() => _saving = true);
    try {
      final res = await ref.read(apiClientProvider).post('/purchases', data: {
        'supplier_id': _supplierId,
        'date': _dateFmt.format(_date),
        if (_destId != null) 'destination': _destId,
        'items': _lines.map((l) => {
              'item_id': l.itemId,
              'price': l.price,
              'qty': l.qty,
              'uom': l.uom,
            }).toList(),
      }).timeout(const Duration(seconds: 15));
      final b = res.data as Map<String, dynamic>;
      if (b['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Purchase saved',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Color(0xFF1A8F33),
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.of(context).pop();
        }
      } else {
        _snack(b['message']?.toString() ?? 'Failed');
      }
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: WakulimaColors.error,
            behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(_purchaseSuppliersProvider).maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final locations = ref.watch(sfLocationsProvider).maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final items = ref.watch(sfStockItemsProvider).maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);

    final grandTotal =
        _lines.fold<double>(0, (s, l) => s + l.total);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar('Add Purchase', _indigo),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Label('Supplier'),
          _Picker(
              value: _supplierLabel,
              hint: 'Select supplier',
              onTap: () => _sheet(context, 'Select Supplier', suppliers,
                  'supplierName', 'supplierId', (id, lbl) {
                setState(() { _supplierId = id; _supplierLabel = lbl; });
              }, fallbackKeys: ['supplier_name', 'full_name', 'company_name', 'title'])),
          const SizedBox(height: 14),

          _Label('Date'),
          _DatePicker(value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 14),

          _Label('Destination'),
          _Picker(
              value: _destLabel,
              hint: 'Select destination',
              onTap: () => _sheet(context, 'Select Destination', locations,
                  'name', 'code', (id, lbl) {
                setState(() { _destId = id; _destLabel = lbl; });
              })),
          const SizedBox(height: 14),

          _Label('Item'),
          _Picker(
              value: _itemLabel,
              hint: 'Select item',
              onTap: () => _sheet(context, 'Select Item', items,
                  'description', 'stock_id', (id, lbl) {
                final it = items.firstWhere(
                    (i) => i['stock_id']?.toString() == id,
                    orElse: () => {});
                setState(() {
                  _itemId = id; _itemLabel = lbl;
                  _itemUom = it['unit']?.toString() ?? 'PCS';
                });
              })),
          const SizedBox(height: 14),

          _Label('Price'),
          const SizedBox(height: 6),
          _NumField(controller: _priceCtrl, hint: '0.00'),
          const SizedBox(height: 14),

          Row(children: [
            const Expanded(child: _Label('Quantity')),
            if (_itemUom.isNotEmpty)
              Text('Uom: $_itemUom',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _indigoBright)),
          ]),
          const SizedBox(height: 6),
          _NumField(controller: _qtyCtrl, hint: '0'),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _indigo,
                  side: const BorderSide(color: _indigo),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
          const SizedBox(height: 20),

          const Text('Items',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WakulimaColors.ink)),
          const SizedBox(height: 8),
          _CartTable(
            headers: const ['Item', 'Price', 'Quantity'],
            rows: _lines.map((l) => [
                  l.description,
                  l.price.toStringAsFixed(2),
                  '${l.qty % 1 == 0 ? l.qty.toInt() : l.qty} ${l.uom}',
                ]).toList(),
            emptyMsg: 'No items added yet.',
            onRemove: (i) => setState(() => _lines.removeAt(i)),
            footer: Row(children: [
              const Text('Total',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: WakulimaColors.ink)),
              const Spacer(),
              Text('KES ${grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _indigo)),
            ]),
          ),
          const SizedBox(height: 24),

          _SaveBtn(label: 'Save Purchase', saving: _saving, onPressed: _save),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Create Supplier Screen ───────────────────────────────────────────────────

class _CreateSupplierScreen extends ConsumerStatefulWidget {
  const _CreateSupplierScreen();

  @override
  ConsumerState<_CreateSupplierScreen> createState() =>
      _CreateSupplierScreenState();
}

class _CreateSupplierScreenState
    extends ConsumerState<_CreateSupplierScreen> {
  final _nameCtrl = TextEditingController();
  final _shortNameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _phone2Ctrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _shortNameCtrl, _pinCtrl, _idCtrl,
      _phoneCtrl, _phone2Ctrl, _contactCtrl, _addressCtrl, _notesCtrl,
    ]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Supplier name is required');
      return;
    }
    setState(() => _saving = true);
    try {
      final res =
          await ref.read(apiClientProvider).post('/purchases/suppliers', data: {
        'name': _nameCtrl.text.trim(),
        'short_name': _shortNameCtrl.text.trim(),
        'pin_no': _pinCtrl.text.trim(),
        'id_no': _idCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'phone2': _phone2Ctrl.text.trim(),
        'contact_person': _contactCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      }).timeout(const Duration(seconds: 12));
      final b = res.data as Map<String, dynamic>;
      if (b['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Supplier created',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Color(0xFF1A8F33),
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.of(context).pop();
        }
      } else {
        _snack(b['message']?.toString() ?? 'Failed');
      }
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: WakulimaColors.error,
            behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar('Create Supplier', _indigo),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Basic Info'),
          const SizedBox(height: 12),
          _Label('Supplier Name'),
          const SizedBox(height: 6),
          _TextField(controller: _nameCtrl),
          const SizedBox(height: 14),
          _Label('Short Name'),
          const SizedBox(height: 6),
          _TextField(controller: _shortNameCtrl),
          const SizedBox(height: 14),
          _Label('Pin No'),
          const SizedBox(height: 6),
          _TextField(controller: _pinCtrl),
          const SizedBox(height: 14),
          _Label('ID No'),
          const SizedBox(height: 6),
          _TextField(controller: _idCtrl),
          const SizedBox(height: 24),

          _SectionLabel('Contact Info'),
          const SizedBox(height: 12),
          _Label('Phone Number'),
          const SizedBox(height: 6),
          _TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 14),
          _Label('Secondary Phone Number'),
          const SizedBox(height: 6),
          _TextField(
              controller: _phone2Ctrl,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 14),
          _Label('Contact Person'),
          const SizedBox(height: 6),
          _TextField(controller: _contactCtrl),
          const SizedBox(height: 14),
          _Label('Address'),
          const SizedBox(height: 6),
          _TextField(controller: _addressCtrl, maxLines: 2),
          const SizedBox(height: 14),
          _Label('Notes'),
          const SizedBox(height: 6),
          _TextField(controller: _notesCtrl, maxLines: 3),
          const SizedBox(height: 32),

          _SaveBtn(label: 'Save', saving: _saving, onPressed: _save),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Error helper ─────────────────────────────────────────────────────────────

String _errMsg(dynamic e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message']?.toString() ?? data['error']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final errors = data['errors'];
      if (errors is Map) {
        final first = (errors.values.first as List?)?.first?.toString();
        if (first != null) return first;
      }
    }
    final code = e.response?.statusCode;
    if (code != null) return 'Server error ($code). Please try again.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Request timed out. Check your connection.';
    }
    return 'Network error. Check your connection.';
  }
  return 'Error saving. Please try again.';
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

AppBar _buildAppBar(String title, Color bg) => AppBar(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: Builder(
          builder: (ctx) => IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.of(ctx).pop(),
              )),
      title: Text(title,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 17)),
    );

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: WakulimaColors.ink));
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: WakulimaColors.inkMid));
}

class _Picker extends StatelessWidget {
  final String? value;
  final String hint;
  final bool required;
  final bool showError;
  final VoidCallback onTap;
  const _Picker(
      {this.value, required this.hint, this.required = false, this.showError = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasErr = showError && value == null;
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
              color: hasErr ? const Color(0xFFFCEBEB) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: hasErr
                      ? WakulimaColors.error.withOpacity(0.5)
                      : WakulimaColors.border)),
          child: Row(children: [
            Expanded(
                child: Text(value ?? '',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: value != null
                            ? WakulimaColors.ink
                            : WakulimaColors.inkMuted))),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: WakulimaColors.inkSoft),
          ]),
        ),
      );
  }
}

class _DatePicker extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DatePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final d = await _pickDate(context, value);
          if (d != null) onChanged(d);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WakulimaColors.border)),
          child: Row(children: [
            Text(_dateFmt.format(value),
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: WakulimaColors.ink)),
            const Spacer(),
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: WakulimaColors.inkSoft),
          ]),
        ),
      );
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _NumField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
        ],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: WakulimaColors.inkMuted),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _indigo, width: 1.5)),
        ),
      );
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  const _TextField(
      {required this.controller, this.maxLines = 1, this.keyboardType});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _indigo, width: 1.5)),
        ),
      );
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? color : WakulimaColors.border,
                  width: selected ? 1.5 : 1)),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? color : WakulimaColors.inkSoft)),
        ),
      );
}

class _CartTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final String emptyMsg;
  final void Function(int) onRemove;
  final Widget? footer;
  const _CartTable({
    required this.headers,
    required this.rows,
    required this.emptyMsg,
    required this.onRemove,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Column(children: [
        // Header row
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            Expanded(
                flex: 3,
                child: Text(headers[0],
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: WakulimaColors.inkMuted))),
            Expanded(
                child: Text(headers[1],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: WakulimaColors.inkMuted))),
            Expanded(
                flex: 2,
                child: Text(headers[2],
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: WakulimaColors.inkMuted))),
          ]),
        ),
        const Divider(height: 1),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(emptyMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: WakulimaColors.inkMuted)),
          )
        else
          ...List.generate(rows.length, (i) {
            final r = rows[i];
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(
                      flex: 3,
                      child: Text(r[0],
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: WakulimaColors.ink))),
                  Expanded(
                      child: Text(r[1],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: WakulimaColors.ink))),
                  Expanded(
                      flex: 2,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                        Flexible(
                          child: Text(r[2],
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: WakulimaColors.ink)),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => onRemove(i),
                          child: const Icon(Icons.close,
                              size: 14, color: WakulimaColors.error),
                        ),
                      ])),
                ]),
              ),
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 14, endIndent: 14),
            ]);
          }),
        if (footer != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            child: footer!,
          ),
        ],
      ]),
    );
  }
}

class _SaveBtn extends StatelessWidget {
  final String label;
  final bool saving;
  final VoidCallback onPressed;
  const _SaveBtn(
      {required this.label,
      required this.saving,
      required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: saving ? null : onPressed,
          style: ElevatedButton.styleFrom(
              backgroundColor: _indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0),
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
        ),
      );
}

// ─── Search bottom sheet ──────────────────────────────────────────────────────

void _sheet(
  BuildContext context,
  String title,
  List<Map<String, dynamic>> items,
  String labelKey,
  String codeKey,
  void Function(String id, String label) onPicked, {
  List<String> fallbackKeys = const [],
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SearchSheet(
      title: title,
      items: items,
      labelKey: labelKey,
      codeKey: codeKey,
      fallbackKeys: fallbackKeys,
      onPicked: onPicked,
    ),
  );
}

class _SearchSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String labelKey;
  final String codeKey;
  final List<String> fallbackKeys;
  final void Function(String id, String label) onPicked;
  const _SearchSheet({
    required this.title,
    required this.items,
    required this.labelKey,
    required this.codeKey,
    required this.onPicked,
    this.fallbackKeys = const [],
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                (i[widget.labelKey] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_q.toLowerCase()) ||
                (i[widget.codeKey] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_q.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: WakulimaColors.border,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text(widget.title,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            style:
                const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: WakulimaColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: WakulimaColors.border)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('No results found',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: WakulimaColors.inkMuted)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = filtered[i];
                      final name = () {
                        final v = it[widget.labelKey]?.toString().trim();
                        if (v != null && v.isNotEmpty) return v;
                        for (final k in widget.fallbackKeys) {
                          final fv = it[k]?.toString().trim();
                          if (fv != null && fv.isNotEmpty) return fv;
                        }
                        return '—';
                      }();
                      final code =
                          it[widget.codeKey]?.toString() ?? '';
                      return ListTile(
                        dense: true,
                        title: Text(name,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        subtitle: code.isNotEmpty
                            ? Text(code,
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: WakulimaColors.inkMuted))
                            : null,
                        onTap: () {
                          widget.onPicked(
                              code.isNotEmpty ? code : name, name);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
