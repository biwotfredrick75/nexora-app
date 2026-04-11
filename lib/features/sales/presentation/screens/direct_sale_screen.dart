import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/sales/data/sales_form_shared.dart';

// ── Next-ref provider ─────────────────────────────────────────────────────────

final _invoiceNextRefProvider = FutureProvider.autoDispose<String>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/sales/invoices/next-ref')
        .timeout(const Duration(seconds: 10));
    final body = res.data as Map<String, dynamic>;
    return body['data']?.toString() ?? '';
  } catch (_) {
    return '';
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DirectSaleScreen extends ConsumerStatefulWidget {
  const DirectSaleScreen({super.key});
  @override
  ConsumerState<DirectSaleScreen> createState() => _DirectSaleScreenState();
}

class _DirectSaleScreenState extends ConsumerState<DirectSaleScreen> {
  // Header fields
  String? _debtorNo;
  String? _salespersonId;
  String? _locationId;
  DateTime _invoiceDate = DateTime.now();
  final _refCtrl      = TextEditingController();
  final _custRefCtrl  = TextEditingController();
  final _notesCtrl    = TextEditingController();
  double _discountPct = 0;
  double _shippingCharge = 0;

  // Line items
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
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _addItem(List<Map<String, dynamic>> stockItems) async {
    Map<String, dynamic>? picked;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SfStockPickerSheet(
        items: stockItems,
        onPicked: (item) => picked = item,
      ),
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
        'debtor_no':      _debtorNo,
        'invoice_date':   _fmtDate(_invoiceDate),
        'reference':      _refCtrl.text.trim(),
        'customer_ref':   _custRefCtrl.text.trim(),
        'comments':       _notesCtrl.text.trim(),
        'shipping_charge':  _shippingCharge,
        if (_salespersonId != null) 'salesperson_id': _salespersonId,
        if (_locationId != null)    'location_id': int.tryParse(_locationId!),
        'items': _items.map((i) => i.toMap()).toList(),
      };

      final res = await api.post('/sales/invoices', data: payload);
      final body = res.data as Map<String, dynamic>;

      if (body['success'] != true) {
        _snack(body['message']?.toString() ?? 'Failed to save');
        return;
      }

      final invoiceId = (body['data'] as Map?)?['id']?.toString();
      final invNo     = (body['data'] as Map?)?['inv_no']?.toString() ?? '';

      if (place && invoiceId != null) {
        final placeRes = await api.post('/sales/invoices/$invoiceId/place');
        final placeBody = placeRes.data as Map<String, dynamic>;
        if (placeBody['success'] == true) {
          _snack('Invoice $invNo posted successfully', error: false);
        } else {
          _snack(placeBody['message']?.toString() ?? 'Saved but failed to post');
          return;
        }
      } else {
        _snack('Invoice $invNo saved as draft', error: false);
        }

      if (mounted) context.pop();
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
    final nextRefAsync    = ref.watch(_invoiceNextRefProvider);
    final customersAsync  = ref.watch(sfCustomersProvider);
    final salespersonsAsync = ref.watch(sfSalespersonsProvider);
    final locationsAsync  = ref.watch(sfLocationsProvider);
    final stockAsync      = ref.watch(sfStockItemsProvider);

    // Auto-fill ref when loaded
    nextRefAsync.whenData((ref) {
      if (_refCtrl.text.isEmpty && ref.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refCtrl.text = ref;
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
        title: const Text('Direct Sale Invoice',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WakulimaColors.ink)),
        actions: [
          if (customersAsync.isLoading || stockAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: WakulimaColors.primary700)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Invoice ref ─────────────────────────────────────────
                    const SfSectionLabel('Invoice Reference'),
                    SfTextField(_refCtrl, 'Auto-generated'),
                    const SizedBox(height: 12),

                    // ── Customer ────────────────────────────────────────────
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

                    // ── Date + Customer ref ─────────────────────────────────
                    Row(children: [
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('Invoice Date'),
                            GestureDetector(
                              onTap: _pickDate,
                              child: SfInputBox(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                child: Row(children: [
                                  Expanded(child: Text(_fmtDate(_invoiceDate),
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

                    // ── Salesperson + Warehouse ─────────────────────────────
                    Row(children: [
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
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SfSectionLabel('From Store'),
                            SfDropdown(
                              hint: 'Select',
                              value: _locationId,
                              items: locations.map((l) => DropdownMenuItem(
                                value: l['id']?.toString(),
                                child: Text(
                                    l['location_name']?.toString() ??
                                        l['name']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 12)),
                              )).toList(),
                              onChanged: (v) =>
                                  setState(() => _locationId = v),
                            ),
                          ])),
                    ]),
                    const SizedBox(height: 12),

                    // ── Discount ────────────────────────────────────────────
                    const SfSectionLabel('Overall Discount %'),
                    TextFormField(
                      initialValue: '0',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) =>
                          setState(() => _discountPct = double.tryParse(v) ?? 0),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '0',
                        suffixText: '%',
                        filled: true, fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: WakulimaColors.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: WakulimaColors.border)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: WakulimaColors.primary700, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Invoice items ───────────────────────────────────────
                    Row(children: [
                      const Text('Invoice Items',
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
                        height: 70,
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
                    const SizedBox(height: 90),
                  ]),
            ),
          ),

          // ── Action bar ────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => _submit(place: false),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: WakulimaColors.primary700),
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WakulimaColors.primary700))
                      : const Text('Save Draft',
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
                  onPressed: _submitting ? null : () => _submit(place: true),
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
          ),
        ],
      ),
    );
  }
}
