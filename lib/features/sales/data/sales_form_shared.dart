// Shared providers and widgets used by Direct Sale, Direct Delivery,
// and Order Entry screens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ── Customers ─────────────────────────────────────────────────────────────────

final sfCustomersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api
        .get('/sales/customers', params: {'limit': '500'}).timeout(const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) return _toList(data);
    if (data is Map && data['data'] is List) return _toList(data['data'] as List);
    return [];
  } catch (_) { return []; }
});

// ── Salespersons ──────────────────────────────────────────────────────────────

final sfSalespersonsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res =
        await api.get('/sales/persons').timeout(const Duration(seconds: 10));
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) return _toList(data);
    if (data is Map && data['data'] is List) return _toList(data['data'] as List);
    return [];
  } catch (_) { return []; }
});

// ── Warehouses / Locations ────────────────────────────────────────────────────

final sfLocationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api
        .get('/inventory/locations').timeout(const Duration(seconds: 10));
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) return _toList(data);
    if (data is Map && data['data'] is List) return _toList(data['data'] as List);
    return [];
  } catch (_) { return []; }
});

// ── Inventory items ───────────────────────────────────────────────────────────

final sfStockItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api.get('/inventory/items',
        params: {'limit': '500', 'active': '1'}).timeout(const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) return _toList(data);
    if (data is Map && data['data'] is List) return _toList(data['data'] as List);
    return [];
  } catch (_) { return []; }
});

List<Map<String, dynamic>> _toList(List src) =>
    src.map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// Total cost from an item map (purchase + material + labour + overhead).
double sfItemCost(Map<String, dynamic> item) =>
    ((item['purchase_cost'] as num?)?.toDouble() ?? 0) +
    ((item['material_cost'] as num?)?.toDouble() ?? 0) +
    ((item['labour_cost'] as num?)?.toDouble() ?? 0) +
    ((item['overhead_cost'] as num?)?.toDouble() ?? 0);

// ── Line item model ───────────────────────────────────────────────────────────

class SfLineItem {
  String stockId;
  String description;
  double qty;
  String unit;
  double price;
  double discountPct;
  double costPrice; // for below-cost warning

  SfLineItem({
    required this.stockId,
    required this.description,
    this.qty = 1,
    this.unit = '',
    this.price = 0,
    this.discountPct = 0,
    this.costPrice = 0,
  });

  bool get isBelowCost => costPrice > 0 && price < costPrice;

  double get lineTotal => qty * price * (1 - discountPct / 100);

  Map<String, dynamic> toMap() => {
        'stock_id':    stockId,
        'description': description,
        'qty':         qty,
        'unit':        unit,
        'price':       price,
        'discount_pct': discountPct,
      };
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class SfSectionLabel extends StatelessWidget {
  final String text;
  const SfSectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: WakulimaColors.inkMid)),
      );
}

class SfInputBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const SfInputBox({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: WakulimaColors.border)),
        child: child,
      );
}

class SfDropdown extends StatelessWidget {
  final String hint;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  const SfDropdown({
    super.key,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SfInputBox(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            hint: Text(hint,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: WakulimaColors.inkMuted)),
            isExpanded: true,
            items: items,
            onChanged: onChanged,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: WakulimaColors.ink),
          ),
        ),
      );
}

class SfTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  const SfTextField(this.controller, this.hint,
      {super.key, this.maxLines = 1, this.keyboardType});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
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
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: WakulimaColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: WakulimaColors.primary700, width: 1.5)),
        ),
      );
}

// ── Line item row ─────────────────────────────────────────────────────────────

class SfItemRow extends StatelessWidget {
  final SfLineItem item;
  final VoidCallback onRemove;
  final VoidCallback onUpdate;
  const SfItemRow(
      {super.key,
      required this.item,
      required this.onRemove,
      required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final belowCost = item.isBelowCost;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: belowCost ? const Color(0xFFFFF3F3) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: belowCost ? WakulimaColors.error : WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (belowCost)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: WakulimaColors.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                    'Price KES ${item.price.toStringAsFixed(2)} is below cost KES ${item.costPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: WakulimaColors.error)),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
              child: Text(item.description,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WakulimaColors.ink))),
          GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close,
                  size: 18, color: WakulimaColors.error)),
        ]),
        if (item.stockId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(item.stockId,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: WakulimaColors.inkMuted)),
          ),
        Row(children: [
          _numField('Qty', item.qty.toString(), (v) {
            item.qty = double.tryParse(v) ?? item.qty;
            onUpdate();
          }),
          const SizedBox(width: 8),
          _numField('Unit Price', item.price.toString(), (v) {
            item.price = double.tryParse(v) ?? item.price;
            onUpdate();
          }),
          const SizedBox(width: 8),
          _numField('Disc %', item.discountPct.toString(), (v) {
            item.discountPct = double.tryParse(v) ?? item.discountPct;
            onUpdate();
          }),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Unit: ${item.unit.isEmpty ? '—' : item.unit}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: WakulimaColors.inkMuted)),
          Text('KES ${item.lineTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WakulimaColors.primary700)),
        ]),
      ]),
    );
  }

  Widget _numField(String label, String initial, ValueChanged<String> onChanged) =>
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9,
                color: WakulimaColors.inkMuted)),
        const SizedBox(height: 2),
        TextFormField(
          initialValue: initial,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: WakulimaColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: WakulimaColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: WakulimaColors.primary700)),
          ),
        ),
      ]));
}

// ── Stock picker bottom sheet ─────────────────────────────────────────────────

class SfStockPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onPicked;
  const SfStockPickerSheet(
      {super.key, required this.items, required this.onPicked});
  @override
  State<SfStockPickerSheet> createState() => _SfStockPickerSheetState();
}

class _SfStockPickerSheetState extends State<SfStockPickerSheet> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                (i['description'] ?? i['name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_query.toLowerCase()) ||
                (i['stock_id'] ?? i['item_code'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_query.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
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
          const Text('Select Item',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by code or name…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: WakulimaColors.cream,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                ? const Center(
                    child: Text('No items found',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: WakulimaColors.inkMuted)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      final name = item['description']?.toString() ??
                          item['name']?.toString() ??
                          '';
                      final code = item['stock_id']?.toString() ??
                          item['item_code']?.toString() ??
                          '';
                      final price =
                          (item['price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        dense: true,
                        title: Text(name,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            '$code  ·  KES ${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: WakulimaColors.inkMuted)),
                        onTap: () {
                          widget.onPicked(item);
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

// ── Totals card ───────────────────────────────────────────────────────────────

class SfTotalsCard extends StatelessWidget {
  final double subTotal;
  final double shippingCharge;
  final ValueChanged<double> onShippingChanged;
  const SfTotalsCard({
    super.key,
    required this.subTotal,
    required this.shippingCharge,
    required this.onShippingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final total = subTotal + shippingCharge;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Column(children: [
        _row('Sub-Total', 'KES ${subTotal.toStringAsFixed(2)}'),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Shipping',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMid)),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: shippingCharge.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) =>
                  onShippingChanged(double.tryParse(v) ?? shippingCharge),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: WakulimaColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: WakulimaColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                        color: WakulimaColors.primary700)),
              ),
            ),
          ),
        ]),
        const Divider(height: 18),
        Row(children: [
          const Text('Amount Total',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WakulimaColors.ink)),
          const Spacer(),
          Text('KES ${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WakulimaColors.primary700)),
        ]),
      ]),
    );
  }

  Widget _row(String label, String value) => Row(children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: WakulimaColors.inkMid)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WakulimaColors.ink)),
      ]);
}
