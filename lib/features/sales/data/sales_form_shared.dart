// Shared providers and widgets used by Direct Sale, Direct Delivery,
// and Order Entry screens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/app_constants.dart';
import 'package:wakulima/core/utils/providers.dart';

// ── Customers ─────────────────────────────────────────────────────────────────

class CustomerNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;

  CustomerNotifier(this._ref) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    final box = Hive.box(AppConstants.customersBox);
    final raw = box.get('list');
    if (raw != null) {
      state = AsyncValue.data(
          (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    }
    await _fetchFresh();
  }

  Future<void> _fetchFresh() async {
    try {
      final api = _ref.read(apiClientProvider);
      final res = await api
          .get('/sales/customers', params: {'limit': '500'})
          .timeout(const Duration(seconds: 12));
      final body = res.data as Map<String, dynamic>;
      final data = body['data'];
      List<Map<String, dynamic>> customers = [];
      if (data is List) {
        customers = _toList(data);
      } else if (data is Map && data['data'] is List) {
        customers = _toList(data['data'] as List);
      }
      await Hive.box(AppConstants.customersBox).put('list', customers);
      state = AsyncValue.data(customers);
    } catch (e, st) {
      if (state is! AsyncData) state = AsyncValue.error(e, st);
    }
  }
}

final sfCustomersProvider = StateNotifierProvider<CustomerNotifier,
    AsyncValue<List<Map<String, dynamic>>>>((ref) => CustomerNotifier(ref));

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
  final res = await api
      .get('/inventory/locations').timeout(const Duration(seconds: 10));
  final body = res.data as Map<String, dynamic>;
  final data = body['data'];
  if (data is List) return _toList(data);
  if (data is Map && data['data'] is List) return _toList(data['data'] as List);
  return [];
});

// ── Inventory items (family by locationId) ────────────────────────────────────
// Calls the search endpoint so each item includes a `price` field.
// Pass locationId to get stock filtered to that store; null = all locations.
// Uses all=1 so items without stock still appear (user sees them but gets warned
// if qty is zero; selling-price filter still applies).

final sfStockItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, locationId) async {
  final api = ref.watch(apiClientProvider);
  final params = <String, String>{'limit': '500', 'all': '1'};
  if (locationId != null) params['location_id'] = locationId;
  final res = await api
      .get('/inventory/items/search', params: params)
      .timeout(const Duration(seconds: 15));
  final body = res.data as Map<String, dynamic>;
  final data = body['data'];
  if (data is List) return _toList(data);
  if (data is Map && data['data'] is List) return _toList(data['data'] as List);
  return [];
});

List<Map<String, dynamic>> _toList(List src) =>
    src.map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// Total cost from an item map.
/// The search endpoint returns `standard_cost` (pre-summed); the index endpoint
/// returns individual components. Check both so warnings work regardless of source.
double sfItemCost(Map<String, dynamic> item) {
  final std = (item['standard_cost'] as num?)?.toDouble();
  if (std != null && std > 0) return std;
  return ((item['purchase_cost'] as num?)?.toDouble() ?? 0) +
      ((item['material_cost'] as num?)?.toDouble() ?? 0) +
      ((item['labour_cost'] as num?)?.toDouble() ?? 0) +
      ((item['overhead_cost'] as num?)?.toDouble() ?? 0);
}

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

class SfItemRow extends StatefulWidget {
  final SfLineItem item;
  final VoidCallback onRemove;
  final VoidCallback onUpdate;
  const SfItemRow({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  State<SfItemRow> createState() => _SfItemRowState();
}

class _SfItemRowState extends State<SfItemRow> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discCtrl;
  late final FocusNode _qtyFocus;
  late final FocusNode _priceFocus;
  late final FocusNode _discFocus;

  @override
  void initState() {
    super.initState();
    _qtyCtrl   = TextEditingController(text: widget.item.qty.toStringAsFixed(1));
    _priceCtrl = TextEditingController(text: widget.item.price.toStringAsFixed(2));
    _discCtrl  = TextEditingController(text: widget.item.discountPct.toStringAsFixed(1));

    // Notify parent only when focus leaves all three fields, so the parent
    // setState (which recomputes totals) doesn't fire on every keystroke.
    _qtyFocus   = FocusNode()..addListener(_onFocusChange);
    _priceFocus = FocusNode()..addListener(_onFocusChange);
    _discFocus  = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final anyFocused =
        _qtyFocus.hasFocus || _priceFocus.hasFocus || _discFocus.hasFocus;
    if (!anyFocused) widget.onUpdate();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _discCtrl.dispose();
    _qtyFocus.dispose();
    _priceFocus.dispose();
    _discFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final belowCost = widget.item.isBelowCost;
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
                    'Price KES ${widget.item.price.toStringAsFixed(2)} is below cost KES ${widget.item.costPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: WakulimaColors.error)),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
              child: Text(widget.item.description,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WakulimaColors.ink))),
          GestureDetector(
              onTap: widget.onRemove,
              child: const Icon(Icons.close,
                  size: 18, color: WakulimaColors.error)),
        ]),
        if (widget.item.stockId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(widget.item.stockId,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: WakulimaColors.inkMuted)),
          ),
        Row(children: [
          _numField('Qty', _qtyCtrl, _qtyFocus, (v) {
            widget.item.qty = double.tryParse(v) ?? widget.item.qty;
            setState(() {}); // refresh line total within the row only
          }),
          const SizedBox(width: 8),
          _numField('Unit Price', _priceCtrl, _priceFocus, (v) {
            widget.item.price = double.tryParse(v) ?? widget.item.price;
            setState(() {});
          }),
          const SizedBox(width: 8),
          _numField('Disc %', _discCtrl, _discFocus, (v) {
            widget.item.discountPct = double.tryParse(v) ?? widget.item.discountPct;
            setState(() {});
          }),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Unit: ${widget.item.unit.isEmpty ? '—' : widget.item.unit}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: WakulimaColors.inkMuted)),
          Text('KES ${widget.item.lineTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WakulimaColors.primary700)),
        ]),
      ]),
    );
  }

  Widget _numField(
    String label,
    TextEditingController ctrl,
    FocusNode focusNode,
    ValueChanged<String> onChanged,
  ) =>
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9,
                color: WakulimaColors.inkMuted)),
        const SizedBox(height: 2),
        TextField(
          controller: ctrl,
          focusNode: focusNode,
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
                borderSide: const BorderSide(
                    color: WakulimaColors.primary700)),
          ),
        ),
      ]));
}

// ── Generic searchable picker ─────────────────────────────────────────────────

class SfSearchPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) labelFn;
  final String? Function(Map<String, dynamic>)? subLabelFn;
  final bool Function(Map<String, dynamic>, String)? searchFn;
  final ValueChanged<Map<String, dynamic>> onPicked;

  const SfSearchPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.labelFn,
    this.subLabelFn,
    this.searchFn,
    required this.onPicked,
  });

  @override
  State<SfSearchPickerSheet> createState() => _SfSearchPickerSheetState();
}

class _SfSearchPickerSheetState extends State<SfSearchPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items.where((item) {
            final q = _query.toLowerCase();
            if (widget.searchFn != null) return widget.searchFn!(item, q);
            return widget.labelFn(item).toLowerCase().contains(q);
          }).toList();

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
          Text(widget.title,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: WakulimaColors.cream,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: WakulimaColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: WakulimaColors.border)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No results found',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: WakulimaColors.inkMuted)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      final sub = widget.subLabelFn?.call(item);
                      return ListTile(
                        dense: true,
                        title: Text(widget.labelFn(item),
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        subtitle: sub != null && sub.isNotEmpty
                            ? Text(sub,
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: WakulimaColors.inkMuted))
                            : null,
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

class SfSearchField extends StatelessWidget {
  final String hint;
  final String? selectedValue;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) valueFn;
  final String Function(Map<String, dynamic>) labelFn;
  final String? Function(Map<String, dynamic>)? subLabelFn;
  final bool Function(Map<String, dynamic>, String)? searchFn;
  final String pickerTitle;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const SfSearchField({
    super.key,
    required this.hint,
    required this.selectedValue,
    required this.items,
    required this.valueFn,
    required this.labelFn,
    this.subLabelFn,
    this.searchFn,
    required this.pickerTitle,
    required this.onChanged,
  });

  String _displayLabel() {
    if (selectedValue == null) return '';
    final match =
        items.where((i) => valueFn(i) == selectedValue).firstOrNull;
    return match != null ? labelFn(match) : selectedValue!;
  }

  @override
  Widget build(BuildContext context) {
    final label = _displayLabel();
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => SfSearchPickerSheet(
          title: pickerTitle,
          items: items,
          labelFn: labelFn,
          subLabelFn: subLabelFn,
          searchFn: searchFn,
          onPicked: onChanged,
        ),
      ),
      child: SfInputBox(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Text(
              label.isEmpty ? hint : label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: selectedValue != null
                      ? WakulimaColors.ink
                      : WakulimaColors.inkMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.keyboard_arrow_down,
              size: 20, color: WakulimaColors.inkMid),
        ]),
      ),
    );
  }
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
