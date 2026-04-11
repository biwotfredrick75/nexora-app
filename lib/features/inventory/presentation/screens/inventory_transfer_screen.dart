import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ─── Mode ─────────────────────────────────────────────────────────────────────

/// [transferOut] = from user's location → they pick destination
/// [request]     = from another store → to user's location
enum TransferMode { transferOut, request }

// ─── Providers ────────────────────────────────────────────────────────────────

final _locationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api
        .get('/inventory/locations')
        .timeout(const Duration(seconds: 15));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final raw = body['data'];
    return (raw is List ? raw : [])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .where((l) => l['inactive'] != true)
        .toList();
  } catch (_) {
    return [];
  }
});

final _itemSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, query) async {
  if (query.length < 2) return [];
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api
        .get('/inventory/items/search', params: {'q': query, 'per_page': '20'})
        .timeout(const Duration(seconds: 10));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final raw = body['data'];
    return (raw is List ? raw : (raw is Map ? raw['data'] ?? [] : []))
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class InventoryTransferScreen extends ConsumerStatefulWidget {
  final TransferMode mode;
  const InventoryTransferScreen({super.key, required this.mode});

  @override
  ConsumerState<InventoryTransferScreen> createState() =>
      _InventoryTransferScreenState();
}

class _InventoryTransferScreenState
    extends ConsumerState<InventoryTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _memoCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String? _otherLocationCode; // destination (transferOut) or source (request)
  bool _submitting = false;
  String? _error;

  final List<_LineItem> _items = [];

  String get _userLocCode {
    final user = Hive.box('auth').get('user') as Map? ?? {};
    return user['loc_code']?.toString() ?? '';
  }

  String get _title =>
      widget.mode == TransferMode.transferOut ? 'Transfer Out' : 'Transfer Request';

  String get _fromCode => widget.mode == TransferMode.transferOut
      ? _userLocCode
      : (_otherLocationCode ?? '');

  String get _toCode => widget.mode == TransferMode.transferOut
      ? (_otherLocationCode ?? '')
      : _userLocCode;

  // ── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submit(bool andSubmit) async {
    if (!_formKey.currentState!.validate()) return;
    if (_otherLocationCode == null) {
      setState(() => _error = widget.mode == TransferMode.transferOut
          ? 'Please select a destination location'
          : 'Please select a source location');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Add at least one item');
      return;
    }
    for (final it in _items) {
      if (it.stockId.isEmpty || it.qty <= 0) {
        setState(() => _error = 'All items must have a stock item and quantity > 0');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final payload = {
        'from_location_id': _fromCode,
        'to_location_id': _toCode,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'memo': _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        'vehicle':
            _vehicleCtrl.text.trim().isEmpty ? null : _vehicleCtrl.text.trim(),
        'items': _items
            .map((i) => {'stock_id': i.stockId, 'quantity': i.qty})
            .toList(),
      };

      final res = await api
          .post('/inventory/transfers', data: payload)
          .timeout(const Duration(seconds: 20));
      final body = res.data as Map<String, dynamic>;
      if (body['success'] != true) {
        setState(() => _error = body['message']?.toString() ?? 'Failed to create transfer');
        return;
      }

      final created = body['data'] as Map<String, dynamic>;
      final id = created['id'] as int;

      if (andSubmit) {
        await api
            .post('/inventory/transfers/$id/submit')
            .timeout(const Duration(seconds: 10));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(andSubmit
              ? 'Transfer submitted for approval'
              : 'Transfer saved as draft'),
          backgroundColor: WakulimaColors.inventory,
        ));
        context.pop();
      }
    } catch (e) {
      setState(
          () => _error = 'Network error. Check connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    _vehicleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(_locationsProvider);
    final accentColor = widget.mode == TransferMode.transferOut
        ? WakulimaColors.inventory
        : const Color(0xFF00897B);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Direction Banner ──────────────────────────────────────────────
            _DirectionBanner(
              mode: widget.mode,
              userLocCode: _userLocCode,
              otherLocCode: _otherLocationCode,
              accentColor: accentColor,
            ),
            const SizedBox(height: 16),

            // ── Location Picker ──────────────────────────────────────────────
            _SectionCard(
              title: widget.mode == TransferMode.transferOut
                  ? 'Destination Location'
                  : 'Source Location',
              icon: Icons.location_on_outlined,
              accentColor: accentColor,
              child: locationsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Failed to load locations',
                      style: TextStyle(color: WakulimaColors.error)),
                ),
                data: (locs) {
                  final filtered = locs
                      .where((l) => l['code'] != _userLocCode)
                      .toList();
                  return _LocationPicker(
                    locations: filtered,
                    selected: _otherLocationCode,
                    accentColor: accentColor,
                    onChanged: (v) => setState(() => _otherLocationCode = v),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ── Date & Vehicle ────────────────────────────────────────────────
            _SectionCard(
              title: 'Transfer Details',
              icon: Icons.calendar_today_outlined,
              accentColor: accentColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(children: [
                  _DateField(
                    date: _date,
                    accentColor: accentColor,
                    onChanged: (d) => setState(() => _date = d),
                  ),
                  const SizedBox(height: 10),
                  _AppTextField(
                    controller: _vehicleCtrl,
                    label: 'Vehicle / Route (optional)',
                    icon: Icons.directions_car_outlined,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 10),
                  _AppTextField(
                    controller: _memoCtrl,
                    label: 'Memo / Notes (optional)',
                    icon: Icons.notes_outlined,
                    accentColor: accentColor,
                    maxLines: 2,
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // ── Items ─────────────────────────────────────────────────────────
            _SectionCard(
              title: 'Items (${_items.length})',
              icon: Icons.inventory_outlined,
              accentColor: accentColor,
              trailing: IconButton(
                onPressed: () {
                  setState(() => _items.add(_LineItem()));
                },
                icon: Icon(Icons.add_circle_outline,
                    color: accentColor, size: 22),
                tooltip: 'Add item',
              ),
              child: _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(children: [
                          Icon(Icons.add_box_outlined,
                              size: 36,
                              color: accentColor.withOpacity(0.4)),
                          const SizedBox(height: 8),
                          const Text('Tap + to add items',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: WakulimaColors.inkMuted)),
                        ]),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Column(
                        children: List.generate(
                          _items.length,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ItemRow(
                              key: ValueKey(_items[i].key),
                              item: _items[i],
                              accentColor: accentColor,
                              onRemove: () =>
                                  setState(() => _items.removeAt(i)),
                              onChanged: () => setState(() {}),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // ── Error ─────────────────────────────────────────────────────────
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFEEEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WakulimaColors.error.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      color: WakulimaColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: WakulimaColors.error)),
                  ),
                ]),
              ),

            // ── Action Buttons ────────────────────────────────────────────────
            if (_submitting)
              const Center(child: CircularProgressIndicator())
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _submit(false),
                    icon: Icon(Icons.save_outlined, size: 15, color: accentColor),
                    label: Text('Draft',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: accentColor)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(color: accentColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _submit(true),
                    icon: const Icon(Icons.send_outlined, size: 15),
                    label: Text(
                        widget.mode == TransferMode.transferOut
                            ? 'Submit for Approval'
                            : 'Send Request',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─── Direction Banner ─────────────────────────────────────────────────────────

class _DirectionBanner extends StatelessWidget {
  final TransferMode mode;
  final String userLocCode;
  final String? otherLocCode;
  final Color accentColor;
  const _DirectionBanner(
      {required this.mode,
      required this.userLocCode,
      required this.otherLocCode,
      required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final fromCode =
        mode == TransferMode.transferOut ? userLocCode : (otherLocCode ?? '...');
    final toCode =
        mode == TransferMode.transferOut ? (otherLocCode ?? '...') : userLocCode;
    final fromLabel =
        mode == TransferMode.transferOut ? 'Your Store' : 'Source';
    final toLabel =
        mode == TransferMode.transferOut ? 'Destination' : 'Your Store';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withOpacity(0.25))),
      child: Row(children: [
        _LocBox(code: fromCode, label: fromLabel, color: accentColor),
        Expanded(
          child: Column(children: [
            Icon(Icons.arrow_forward_rounded, color: accentColor, size: 22),
            Text(
                mode == TransferMode.transferOut
                    ? 'Transfer Out'
                    : 'Request In',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
          ]),
        ),
        _LocBox(code: toCode, label: toLabel, color: accentColor),
      ]),
    );
  }
}

class _LocBox extends StatelessWidget {
  final String code;
  final String label;
  final Color color;
  const _LocBox(
      {required this.code, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10)),
        child: Text(code,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: color)),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: WakulimaColors.inkMuted)),
    ]);
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;
  const _SectionCard(
      {required this.title,
      required this.icon,
      required this.accentColor,
      required this.child,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Row(children: [
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(width: 7),
            Text(title,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor)),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
        ),
        Divider(height: 1, color: WakulimaColors.border.withOpacity(0.7)),
        child,
      ]),
    );
  }
}

// ─── Location Picker ──────────────────────────────────────────────────────────

class _LocationPicker extends StatefulWidget {
  final List<Map<String, dynamic>> locations;
  final String? selected;
  final Color accentColor;
  final ValueChanged<String?> onChanged;
  const _LocationPicker(
      {required this.locations,
      required this.selected,
      required this.accentColor,
      required this.onChanged});

  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.locations.where((l) {
      if (_q.isEmpty) return true;
      final code = l['code']?.toString().toLowerCase() ?? '';
      final name = l['name']?.toString().toLowerCase() ?? '';
      return code.contains(_q) || name.contains(_q);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
              color: WakulimaColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WakulimaColors.border)),
          child: Row(children: [
            const SizedBox(width: 10),
            const Icon(Icons.search_rounded, size: 16, color: WakulimaColors.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                decoration: const InputDecoration(
                    hintText: 'Search location…',
                    hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: WakulimaColors.inkMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onChanged: (v) => setState(() => _q = v.toLowerCase()),
              ),
            ),
          ]),
        ),
      ),
      SizedBox(
        height: 180,
        child: filtered.isEmpty
            ? const Center(
                child: Text('No locations found',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: WakulimaColors.inkMuted)))
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final loc = filtered[i];
                  final code = loc['code']?.toString() ?? '';
                  final name = loc['name']?.toString() ?? '';
                  final selected = widget.selected == code;
                  return InkWell(
                    onTap: () => widget.onChanged(code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                          color: selected
                              ? widget.accentColor.withOpacity(0.07)
                              : Colors.transparent,
                          border: Border(
                              bottom: BorderSide(
                                  color: WakulimaColors.border.withOpacity(0.5)))),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: selected
                                  ? widget.accentColor.withOpacity(0.15)
                                  : const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(code,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? widget.accentColor
                                      : WakulimaColors.inkSoft)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(name,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: WakulimaColors.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (selected)
                          Icon(Icons.check_circle_rounded,
                              size: 18, color: widget.accentColor),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ─── Date Field ───────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final DateTime date;
  final Color accentColor;
  final ValueChanged<DateTime> onChanged;
  const _DateField(
      {required this.date,
      required this.accentColor,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 30)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.light(primary: accentColor),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: WakulimaColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WakulimaColors.border)),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 16, color: accentColor),
          const SizedBox(width: 10),
          Text(DateFormat('dd MMM yyyy').format(date),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.ink)),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 16, color: WakulimaColors.inkMuted),
        ]),
      ),
    );
  }
}

// ─── Text Field ───────────────────────────────────────────────────────────────

class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accentColor;
  final int maxLines;
  const _AppTextField(
      {required this.controller,
      required this.label,
      required this.icon,
      required this.accentColor,
      this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted),
        prefixIcon: Icon(icon, size: 18, color: accentColor),
        filled: true,
        fillColor: WakulimaColors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: WakulimaColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: WakulimaColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accentColor, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }
}

// ─── Line Item Model ──────────────────────────────────────────────────────────

class _LineItem {
  final String key = UniqueKey().toString();
  String stockId = '';
  String description = '';
  double qty = 0;
}

// ─── Item Row ─────────────────────────────────────────────────────────────────

class _ItemRow extends ConsumerStatefulWidget {
  final _LineItem item;
  final Color accentColor;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  const _ItemRow(
      {super.key,
      required this.item,
      required this.accentColor,
      required this.onRemove,
      required this.onChanged});

  @override
  ConsumerState<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<_ItemRow> {
  final _itemCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  bool _showDropdown = false;
  String _searchQ = '';

  @override
  void initState() {
    super.initState();
    if (widget.item.stockId.isNotEmpty) {
      _itemCtrl.text =
          '${widget.item.stockId} — ${widget.item.description}';
    }
    _qtyCtrl.text = widget.item.qty > 0 ? widget.item.qty.toString() : '';
    _itemFocus.addListener(() {
      if (!_itemFocus.hasFocus) setState(() => _showDropdown = false);
    });
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _qtyCtrl.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(_itemSearchProvider(_searchQ));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: WakulimaColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Column(children: [
              TextFormField(
                controller: _itemCtrl,
                focusNode: _itemFocus,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search item…',
                  hintStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: WakulimaColors.inkMuted),
                  prefixIcon: Icon(Icons.inventory_outlined,
                      size: 16, color: widget.accentColor),
                  filled: true,
                  fillColor: Colors.white,
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
                      borderSide: BorderSide(
                          color: widget.accentColor, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  isDense: true,
                ),
                onChanged: (v) {
                  setState(() {
                    _searchQ = v;
                    _showDropdown = v.length >= 2;
                    // Clear selection if user types again
                    if (widget.item.stockId.isNotEmpty &&
                        v != '${widget.item.stockId} — ${widget.item.description}') {
                      widget.item.stockId = '';
                      widget.item.description = '';
                      widget.onChanged();
                    }
                  });
                },
              ),
              // Dropdown
              if (_showDropdown)
                searchAsync.when(
                  loading: () => Container(
                    height: 44,
                    color: Colors.white,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const SizedBox(),
                  data: (results) => results.isEmpty
                      ? Container(
                          height: 36,
                          color: Colors.white,
                          child: const Center(
                              child: Text('No items found',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      color: WakulimaColors.inkMuted))))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(8)),
                              border: Border.all(
                                  color: widget.accentColor.withOpacity(0.4)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4))
                              ]),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final it = results[i];
                              final sid =
                                  it['stock_id']?.toString() ?? '';
                              final desc =
                                  it['description']?.toString() ?? '';
                              return InkWell(
                                onTap: () {
                                  widget.item.stockId = sid;
                                  widget.item.description = desc;
                                  _itemCtrl.text = '$sid — $desc';
                                  setState(() => _showDropdown = false);
                                  _itemFocus.unfocus();
                                  widget.onChanged();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: widget.accentColor
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: Text(sid,
                                          style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: widget.accentColor)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(desc,
                                          style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          // Quantity field
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: _qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Qty',
                hintStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: WakulimaColors.inkMuted),
                filled: true,
                fillColor: Colors.white,
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
                    borderSide: BorderSide(
                        color: widget.accentColor, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
              onChanged: (v) {
                widget.item.qty = double.tryParse(v) ?? 0;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 4),
          // Remove
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.remove_circle_outline,
                color: WakulimaColors.error, size: 20),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ]),
      ]),
    );
  }
}
