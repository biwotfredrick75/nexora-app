import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/sales/data/sales_form_shared.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _orderNextRefProvider = FutureProvider.autoDispose<String>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/sales/orders/next-ref')
        .timeout(const Duration(seconds: 10));
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is Map) return data['ref']?.toString() ?? '';
    return data?.toString() ?? '';
  } catch (_) {
    return '';
  }
});

final _ordersListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final now = DateTime.now();
  final from =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
  final to =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  try {
    final res = await api.get('/sales/orders',
        params: {'date_from': from, 'date_to': to, 'limit': '100'}).timeout(
        const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final data = body['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  } catch (_) {
    return [];
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class OrderEntryScreen extends ConsumerStatefulWidget {
  const OrderEntryScreen({super.key});
  @override
  ConsumerState<OrderEntryScreen> createState() => _OrderEntryScreenState();
}

class _OrderEntryScreenState extends ConsumerState<OrderEntryScreen> {
  bool _showForm = false;

  String? _debtorNo;
  String? _salespersonId;
  String? _locationId;
  DateTime _orderDate = DateTime.now();
  final _refCtrl      = TextEditingController();
  final _custRefCtrl  = TextEditingController();
  final _notesCtrl    = TextEditingController();
  double _discountPct    = 0;
  double _shippingCharge = 0;

  final List<SfLineItem> _items = [];
  bool _submitting = false;

  @override
  void dispose() {
    _refCtrl.dispose();
    _custRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double get _subTotal =>
      _items.fold(0.0, (s, i) => s + i.lineTotal) * (1 - _discountPct / 100);
  double get _total => _subTotal + _shippingCharge;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _orderDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030));
    if (picked != null) setState(() => _orderDate = picked);
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
      final sellingPrice = (picked!['price'] as num?)?.toDouble() ?? 0;
      if (sellingPrice <= 0) {
        _snack(
          'No selling price set for "${picked!['description'] ?? picked!['name']}". '
          'Please set a selling price in the system before adding this item.',
          error: true,
        );
        return;
      }
      setState(() => _items.add(SfLineItem(
            stockId: picked!['stock_id']?.toString() ??
                picked!['item_code']?.toString() ?? '',
            description: picked!['description']?.toString() ??
                picked!['name']?.toString() ?? '',
            unit: picked!['units_id']?.toString() ??
                picked!['unit']?.toString() ?? '',
            price: sellingPrice,
            costPrice: sfItemCost(picked!),
          )));
    }
  }

  void _resetForm() {
    setState(() {
      _debtorNo = null;
      _salespersonId = null;
      _locationId = null;
      _orderDate = DateTime.now();
      _refCtrl.clear();
      _custRefCtrl.clear();
      _notesCtrl.clear();
      _discountPct = 0;
      _shippingCharge = 0;
      _items.clear();
      _showForm = false;
    });
    ref.invalidate(_orderNextRefProvider);
  }

  Future<void> _submit({bool place = false}) async {
    if (_debtorNo == null) { _snack('Select a customer'); return; }
    if (_items.isEmpty)   { _snack('Add at least one item'); return; }

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);

      final payload = {
        'debtor_no':        _debtorNo,
        'order_date':       _fmtDate(_orderDate),
        'reference':        _refCtrl.text.trim(),
        'customer_ref':     _custRefCtrl.text.trim(),
        'comments':         _notesCtrl.text.trim(),
        'discount_percent': _discountPct,
        'shipping_charge':  _shippingCharge,
        if (_salespersonId != null) 'salesperson_id': _salespersonId,
        if (_locationId != null)    'location_id': int.tryParse(_locationId!),
        'items': _items.map((i) => i.toMap()).toList(),
      };

      final res  = await api.post('/sales/orders', data: payload);
      final body = res.data as Map<String, dynamic>;

      if (body['success'] != true) {
        _snack(body['message']?.toString() ?? 'Failed to save');
        return;
      }

      final orderId = (body['data'] as Map?)?['id']?.toString();
      final soNo    = (body['data'] as Map?)?['so_no']?.toString() ?? '';

      if (place && orderId != null) {
        final placeRes  = await api.post('/sales/orders/$orderId/place');
        final placeBody = placeRes.data as Map<String, dynamic>;
        if (placeBody['success'] == true) {
          _snack('Order $soNo placed successfully', error: false);
        } else {
          _snack(placeBody['message']?.toString() ?? 'Saved but failed to place');
          return;
        }
      } else {
        _snack('Order $soNo saved as draft', error: false);
      }

      ref.invalidate(_ordersListProvider);
      _resetForm();
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg = 'Failed to save order';
      if (data is Map) {
        msg = data['message']?.toString() ?? msg;
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          msg = errors.values.first?.toString() ?? msg;
        }
      }
      _snack(msg);
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
    final nextRefAsync      = ref.watch(_orderNextRefProvider);
    final ordersAsync       = ref.watch(_ordersListProvider);
    final customersAsync    = ref.watch(sfCustomersProvider);
    final salespersonsAsync = ref.watch(sfSalespersonsProvider);
    final locationsAsync    = ref.watch(sfLocationsProvider);
    final stockAsync        = ref.watch(sfStockItemsProvider(_locationId));

    nextRefAsync.whenData((r) {
      if (_refCtrl.text.isEmpty && r.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refCtrl.text = r;
        });
      }
    });

    final customers    = customersAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final salespersons = salespersonsAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final locations    = locationsAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final locationsError = locationsAsync.maybeWhen(error: (e, _) => e.toString(), orElse: () => null);
    final stockItems   = stockAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[])
        .where((i) => ((i['price'] as num?)?.toDouble() ?? 0) > 0).toList();
    final stockError   = stockAsync.maybeWhen(error: (e, _) => e.toString(), orElse: () => null);
    final stockLoading = stockAsync.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
          onPressed: () => context.pop(),
        ),
        title: const Text('Sales Order Entry',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WakulimaColors.ink)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: WakulimaColors.primary600),
              onPressed: () => ref.invalidate(_ordersListProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: WakulimaColors.primary700,
        child: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
      ),
      body: Column(children: [
        // ── Order form ──────────────────────────────────────────────────────
        if (_showForm)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ref
                    const SfSectionLabel('Order Reference'),
                    SfTextField(_refCtrl, 'Auto-generated'),
                    const SizedBox(height: 12),

                    // Customer
                    const SfSectionLabel('Customer *'),
                    SfSearchField(
                      hint: 'Select customer',
                      selectedValue: _debtorNo,
                      items: customers,
                      valueFn: (c) => c['debtor_no']?.toString() ?? '',
                      labelFn: (c) => c['name']?.toString() ?? c['debtor_no']?.toString() ?? '',
                      subLabelFn: (c) => c['debtor_no']?.toString(),
                      searchFn: (c, q) =>
                          (c['name'] ?? '').toString().toLowerCase().contains(q) ||
                          (c['debtor_no'] ?? '').toString().toLowerCase().contains(q),
                      pickerTitle: 'Select Customer',
                      onChanged: (c) => setState(() => _debtorNo = c['debtor_no']?.toString()),
                    ),
                    const SizedBox(height: 12),

                    // Order date + Customer ref
                    Row(children: [
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('Order Date'),
                            GestureDetector(
                              onTap: _pickDate,
                              child: SfInputBox(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                child: Row(children: [
                                  Expanded(child: Text(_fmtDate(_orderDate),
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
                            const SfSectionLabel('Customer Ref'),
                            SfTextField(_custRefCtrl, 'e.g. PO-001'),
                          ])),
                    ]),
                    const SizedBox(height: 12),

                    // Salesperson + From Store
                    Row(children: [
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('Salesperson'),
                            SfSearchField(
                              hint: 'Select',
                              selectedValue: _salespersonId,
                              items: salespersons,
                              valueFn: (s) => s['id']?.toString() ?? s['salesperson_id']?.toString() ?? '',
                              labelFn: (s) => s['name']?.toString() ?? s['salesperson_name']?.toString() ?? '',
                              pickerTitle: 'Select Salesperson',
                              onChanged: (s) => setState(() => _salespersonId = (s['id'] ?? s['salesperson_id'])?.toString()),
                            ),
                          ])),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('From Store'),
                            if (locationsError != null)
                              GestureDetector(
                                onTap: () => ref.invalidate(sfLocationsProvider),
                                child: SfInputBox(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  child: Row(children: [
                                    const Icon(Icons.warning_amber_rounded, size: 14, color: WakulimaColors.error),
                                    const SizedBox(width: 6),
                                    const Expanded(child: Text('Tap to retry', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.error))),
                                  ]),
                                ),
                              )
                            else if (locationsAsync.isLoading)
                              SfInputBox(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                child: Row(children: const [
                                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: WakulimaColors.inkMuted)),
                                  SizedBox(width: 8),
                                  Text('Loading…', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.inkMuted)),
                                ]),
                              )
                            else
                              SfSearchField(
                                hint: locations.isEmpty ? 'No stores found' : 'Select',
                                selectedValue: _locationId,
                                items: locations,
                                valueFn: (l) => l['id']?.toString() ?? '',
                                labelFn: (l) => l['name']?.toString() ?? '',
                                pickerTitle: 'Select Store',
                                onChanged: (l) => setState(() {
                                  _locationId = l['id']?.toString();
                                  ref.invalidate(sfStockItemsProvider(_locationId));
                                }),
                              ),
                          ])),
                    ]),
                    const SizedBox(height: 12),

                    // Overall discount
                    const SfSectionLabel('Overall Discount %'),
                    TextFormField(
                      initialValue: '0',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) => setState(
                          () => _discountPct = double.tryParse(v) ?? 0),
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '0',
                        suffixText: '%',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: WakulimaColors.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: WakulimaColors.border)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: WakulimaColors.primary700, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Items
                    Row(children: [
                      const Text('Order Items',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: WakulimaColors.ink)),
                      const Spacer(),
                      if (stockLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: WakulimaColors.primary700)),
                        )
                      else if (stockError != null)
                        TextButton.icon(
                          onPressed: () => ref.invalidate(sfStockItemsProvider(_locationId)),
                          icon: const Icon(Icons.refresh, size: 16, color: WakulimaColors.error),
                          label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.error)),
                        )
                      else
                        TextButton.icon(
                          onPressed: stockItems.isEmpty
                              ? () => _snack(
                                  _locationId == null
                                      ? 'Select a store first, or no items have a selling price set'
                                      : 'No items with a selling price found in this store',
                                  error: false)
                              : () => _addItem(stockItems),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Add Item',
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13)),
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
                          onPressed: _submitting
                              ? null
                              : () => _submit(place: true),
                          style: FilledButton.styleFrom(
                              backgroundColor: WakulimaColors.primary700,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13)),
                          child: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(
                                  'Place Order  ·  KES ${_total.toStringAsFixed(2)}',
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
          // ── Orders list ───────────────────────────────────────────────────
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: WakulimaColors.primary700, strokeWidth: 2)),
              error: (_, __) => _empty('Failed to load orders'),
              data: (orders) => orders.isEmpty
                  ? _empty('No orders this month')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _OrderTile(order: orders[i]),
                    ),
            ),
          ),
      ]),
    );
  }

  static Widget _empty(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_outlined,
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

// ── Order list tile ───────────────────────────────────────────────────────────

class _OrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? 'draft';
    final colors = _statusColors(status);
    final total  = (order['amount_total'] as num?)?.toDouble() ?? 0;
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
              color: WakulimaColors.primary50,
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.shopping_cart_outlined,
              size: 20, color: WakulimaColors.primary700),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(order['so_no']?.toString() ?? '—',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WakulimaColors.ink)),
              Text(
                  '${order['debtor_no'] ?? order['customer_name'] ?? ''}  ·  ${order['order_date'] ?? ''}',
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
