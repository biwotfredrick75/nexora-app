import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/sales/data/sales_form_shared.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _deliveryNextRefProvider = FutureProvider.autoDispose<String>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/sales/deliveries/next-ref')
        .timeout(const Duration(seconds: 10));
    final body = res.data as Map<String, dynamic>;
    return body['data']?.toString() ?? '';
  } catch (_) {
    return '';
  }
});

final _deliveriesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final now = DateTime.now();
  final from =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
  final to =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  try {
    final res = await api.get('/sales/deliveries',
        params: {'date_from': from, 'date_to': to, 'limit': '100'}).timeout(
        const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final data = body['data'];
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  } catch (_) {
    return [];
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DirectDeliveryScreen extends ConsumerStatefulWidget {
  const DirectDeliveryScreen({super.key});
  @override
  ConsumerState<DirectDeliveryScreen> createState() =>
      _DirectDeliveryScreenState();
}

class _DirectDeliveryScreenState extends ConsumerState<DirectDeliveryScreen> {
  bool _showForm = false;

  String? _debtorNo;
  String? _salespersonId;
  String? _locationId;
  DateTime _deliveryDate = DateTime.now();
  final _refCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();
  double _shippingCharge = 0;

  final List<SfLineItem> _items = [];
  bool _submitting = false;

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double get _subTotal => _items.fold(0.0, (s, i) => s + i.lineTotal);
  double get _total    => _subTotal + _shippingCharge;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _deliveryDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030));
    if (picked != null) setState(() => _deliveryDate = picked);
  }

  Future<void> _addItem(List<Map<String, dynamic>> stockItems) async {
    Map<String, dynamic>? picked;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          SfStockPickerSheet(items: stockItems, onPicked: (i) => picked = i),
    );
    if (picked != null && mounted) {
      setState(() => _items.add(SfLineItem(
            stockId: picked!['stock_id']?.toString() ??
                picked!['item_code']?.toString() ?? '',
            description: picked!['description']?.toString() ??
                picked!['name']?.toString() ?? '',
            unit: picked!['units_id']?.toString() ??
                picked!['unit']?.toString() ?? '',
            price: (picked!['price'] as num?)?.toDouble() ?? 0,
            costPrice: sfItemCost(picked!),
          )));
    }
  }

  void _resetForm() {
    setState(() {
      _debtorNo = null;
      _salespersonId = null;
      _locationId = null;
      _deliveryDate = DateTime.now();
      _refCtrl.clear();
      _notesCtrl.clear();
      _shippingCharge = 0;
      _items.clear();
      _showForm = false;
    });
    ref.invalidate(_deliveryNextRefProvider);
  }

  Future<void> _submit({bool place = false}) async {
    if (_debtorNo == null) { _snack('Select a customer'); return; }
    if (_items.isEmpty)   { _snack('Add at least one item'); return; }
    final belowCost = _items.where((i) => i.isBelowCost).toList();
    if (belowCost.isNotEmpty) {
      _snack('${belowCost.first.description}: price is below cost. Please correct before saving.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);

      final payload = {
        'debtor_no':       _debtorNo,
        'delivery_date':   _fmtDate(_deliveryDate),
        'reference':       _refCtrl.text.trim(),
        'comments':        _notesCtrl.text.trim(),
        'shipping_charge': _shippingCharge,
        if (_salespersonId != null) 'salesperson_id': _salespersonId,
        if (_locationId != null)    'location_id': int.tryParse(_locationId!),
        'items': _items.map((i) => i.toMap()).toList(),
      };

      final res  = await api.post('/sales/deliveries', data: payload);
      final body = res.data as Map<String, dynamic>;

      if (body['success'] != true) {
        _snack(body['message']?.toString() ?? 'Failed to save');
        return;
      }

      final delivId  = (body['data'] as Map?)?['id']?.toString();
      final delivNo  = (body['data'] as Map?)?['delivery_no']?.toString() ?? '';

      if (place && delivId != null) {
        final placeRes  = await api.post('/sales/deliveries/$delivId/place');
        final placeBody = placeRes.data as Map<String, dynamic>;
        if (placeBody['success'] == true) {
          _snack('Delivery $delivNo posted', error: false);
        } else {
          _snack(placeBody['message']?.toString() ?? 'Saved but failed to post');
          return;
        }
      } else {
        _snack('Delivery $delivNo saved as draft', error: false);
      }

      ref.invalidate(_deliveriesListProvider);
      _resetForm();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool error = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? WakulimaColors.error : WakulimaColors.success,
      ));

  @override
  Widget build(BuildContext context) {
    final nextRefAsync      = ref.watch(_deliveryNextRefProvider);
    final deliveriesAsync   = ref.watch(_deliveriesListProvider);
    final customersAsync    = ref.watch(sfCustomersProvider);
    final salespersonsAsync = ref.watch(sfSalespersonsProvider);
    final locationsAsync    = ref.watch(sfLocationsProvider);
    final stockAsync        = ref.watch(sfStockItemsProvider);

    nextRefAsync.whenData((r) {
      if (_refCtrl.text.isEmpty && r.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refCtrl.text = r;
        });
      }
    });

    final customers    = customersAsync.maybeWhen(data: (d) => d, orElse: () => []);
    final salespersons = salespersonsAsync.maybeWhen(data: (d) => d, orElse: () => []);
    final locations    = locationsAsync.maybeWhen(data: (d) => d, orElse: () => []);
    final stockItems   = stockAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
          onPressed: () => context.pop(),
        ),
        title: const Text('Direct Delivery',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WakulimaColors.ink)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: WakulimaColors.primary600),
              onPressed: () => ref.invalidate(_deliveriesListProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: WakulimaColors.primary700,
        child: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
      ),
      body: Column(children: [
        // ── New delivery form ───────────────────────────────────────────────
        if (_showForm)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ref
                    const SfSectionLabel('Delivery Reference'),
                    SfTextField(_refCtrl, 'Auto-generated'),
                    const SizedBox(height: 12),

                    // Customer
                    const SfSectionLabel('Customer *'),
                    SfDropdown(
                      hint: 'Select customer',
                      value: _debtorNo,
                      items: customers.map((c) => DropdownMenuItem(
                        value: c['debtor_no']?.toString(),
                        child: Text(
                            c['name']?.toString() ?? c['debtor_no']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13)),
                      )).toList(),
                      onChanged: (v) => setState(() => _debtorNo = v),
                    ),
                    const SizedBox(height: 12),

                    // Delivery date
                    Row(children: [
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('Delivery Date'),
                            GestureDetector(
                              onTap: _pickDate,
                              child: SfInputBox(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                child: Row(children: [
                                  Expanded(child: Text(_fmtDate(_deliveryDate),
                                      style: const TextStyle(
                                          fontFamily: 'Poppins', fontSize: 13))),
                                  const Icon(Icons.calendar_today_outlined,
                                      size: 15, color: WakulimaColors.inkMuted),
                                ]),
                              ),
                            ),
                          ])),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('Salesperson'),
                            SfDropdown(
                              hint: 'Select',
                              value: _salespersonId,
                              items: salespersons.map((s) => DropdownMenuItem(
                                value: s['id']?.toString() ??
                                    s['salesperson_id']?.toString(),
                                child: Text(
                                    s['name']?.toString() ??
                                        s['salesperson_name']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 12)),
                              )).toList(),
                              onChanged: (v) =>
                                  setState(() => _salespersonId = v),
                            ),
                          ])),
                    ]),
                    const SizedBox(height: 12),

                    // From Store
                    const SfSectionLabel('From Store'),
                    SfDropdown(
                      hint: 'Select warehouse',
                      value: _locationId,
                      items: locations.map((l) => DropdownMenuItem(
                        value: l['id']?.toString(),
                        child: Text(
                            l['location_name']?.toString() ??
                                l['name']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13)),
                      )).toList(),
                      onChanged: (v) => setState(() => _locationId = v),
                    ),
                    const SizedBox(height: 18),

                    // Items
                    Row(children: [
                      const Text('Delivery Items',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: WakulimaColors.ink)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: stockItems.isEmpty
                            ? null
                            : () => _addItem(stockItems),
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('Add',
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: WakulimaColors.primary700),
                      ),
                    ]),
                    const SizedBox(height: 6),

                    if (_items.isEmpty)
                      Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: WakulimaColors.border)),
                        child: const Text('No items added',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: WakulimaColors.inkMuted)),
                      )
                    else
                      ...List.generate(
                          _items.length,
                          (i) => SfItemRow(
                                item: _items[i],
                                onRemove: () =>
                                    setState(() => _items.removeAt(i)),
                                onUpdate: () => setState(() {}),
                              )),

                    if (_items.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SfTotalsCard(
                        subTotal: _subTotal,
                        shippingCharge: _shippingCharge,
                        onShippingChanged: (v) =>
                            setState(() => _shippingCharge = v),
                      ),
                    ],

                    const SizedBox(height: 12),
                    const SfSectionLabel('Notes'),
                    SfTextField(_notesCtrl, 'Additional notes', maxLines: 2),
                    const SizedBox(height: 12),

                    // Action buttons
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => _submit(place: false),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: WakulimaColors.primary700),
                              padding: const EdgeInsets.symmetric(vertical: 13)),
                          child: const Text('Save Draft',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  color: WakulimaColors.primary700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed:
                              _submitting ? null : () => _submit(place: true),
                          style: FilledButton.styleFrom(
                              backgroundColor: WakulimaColors.primary700,
                              padding: const EdgeInsets.symmetric(vertical: 13)),
                          child: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(
                                  'Post  ·  KES ${_total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ]),
            ),
          )
        else
          // ── Deliveries list ───────────────────────────────────────────────
          Expanded(
            child: deliveriesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: WakulimaColors.primary700, strokeWidth: 2)),
              error: (_, __) => _empty('Failed to load deliveries'),
              data: (deliveries) => deliveries.isEmpty
                  ? _empty('No deliveries this month')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: deliveries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _DeliveryTile(item: deliveries[i]),
                    ),
            ),
          ),
      ]),
    );
  }

  static Widget _empty(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.local_shipping_outlined,
              size: 44, color: WakulimaColors.inkMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMuted)),
        ]),
      );
}

// ── Delivery list tile ────────────────────────────────────────────────────────

class _DeliveryTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DeliveryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString() ?? 'draft';
    final colors = _statusColors(status);
    final total  = (item['amount_total'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: const Color(0xFFE8F5F3),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.local_shipping_outlined,
              size: 20, color: Color(0xFF00897B)),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                  item['delivery_no']?.toString() ??
                      item['id']?.toString() ?? '—',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WakulimaColors.ink)),
              Text(
                  '${item['debtor_no'] ?? item['customer_name'] ?? ''}  ·  ${item['delivery_date'] ?? item['date'] ?? ''}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: WakulimaColors.inkMuted)),
              Text('KES ${_fmt(total)}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: WakulimaColors.inkSoft)),
            ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: colors[0], borderRadius: BorderRadius.circular(20)),
          child: Text(
              status[0].toUpperCase() + status.substring(1),
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors[1])),
        ),
      ]),
    );
  }

  static List<Color> _statusColors(String s) {
    switch (s) {
      case 'placed':    return [const Color(0xFFEAF9EF), const Color(0xFF1A8F33)];
      case 'cancelled': return [const Color(0xFFFFEEEE), WakulimaColors.error];
      default:          return [const Color(0xFFFEF3CD), const Color(0xFF9A6B00)];
    }
  }

  static String _fmt(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
