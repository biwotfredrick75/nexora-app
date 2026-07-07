import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/sales/data/sales_form_shared.dart';

const _partyTypes = [
  {'value': 'farmer', 'label': 'Farmer'},
  {'value': 'employee', 'label': 'Employee'},
  {'value': 'transporter', 'label': 'Transporter'},
];

/// Laravel serializes Eloquent `decimal:N` casts (e.g. qty, unit_price,
/// total_amount) as JSON strings, not numbers — parse either shape defensively.
double _numVal(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

class _EspItem {
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  double get qty => double.tryParse(_qtyCtrl.text) ?? 0;
  double get price => double.tryParse(_priceCtrl.text) ?? 0;
  double get total => qty * price;

  Map<String, dynamic> toMap() => {
        'description': _descCtrl.text.trim(),
        'qty': qty,
        'unit_price': price,
      };

  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
  }
}

/// Create (or edit, when [editSale] is passed) an ESP sale — an external
/// agrovet/service-provider invoicing a farmer, employee or transporter.
/// Party/provider can't change on edit (backend `updateSale` only allows
/// changing items/date/notes), so those fields lock once editing.
class EspSaleScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? editSale;
  const EspSaleScreen({super.key, this.editSale});

  @override
  ConsumerState<EspSaleScreen> createState() => _EspSaleScreenState();
}

class _EspSaleScreenState extends ConsumerState<EspSaleScreen> {
  int? _espId;
  String _partyType = 'farmer';
  int? _partyId;
  DateTime _saleDate = DateTime.now();
  final _notesCtrl = TextEditingController();
  final List<_EspItem> _items = [_EspItem()];

  Map<String, dynamic>? _creditScore;
  bool _loadingCredit = false;
  bool _submitting = false;
  Map<String, dynamic>? _linkedProvider;

  bool get _isEdit => widget.editSale != null;
  /// Provider field is locked whenever editing OR the login is linked to one
  /// agrovet account — the backend always uses the caller's own linked
  /// provider anyway, so letting them pick a different one would be misleading.
  bool get _providerLocked => _isEdit || _linkedProvider != null;

  @override
  void initState() {
    super.initState();
    final s = widget.editSale;
    if (s == null) {
      // New sale: auto-select + lock to the caller's own linked provider, if any.
      _linkedProvider = ref.read(espRepositoryProvider).getLinkedProvider();
      if (_linkedProvider != null) {
        _espId = (_linkedProvider!['id'] as num?)?.toInt();
      }
    }
    if (s != null) {
      _espId = (s['esp_id'] as num?)?.toInt();
      _partyType = s['party_type']?.toString() ?? 'farmer';
      _partyId = (s['party_id'] as num?)?.toInt();
      _notesCtrl.text = s['notes']?.toString() ?? '';
      final items = (s['items'] as List?) ?? [];
      if (items.isNotEmpty) {
        _items.clear();
        for (final raw in items) {
          final m = Map<String, dynamic>.from(raw as Map);
          final item = _EspItem();
          item._descCtrl.text = m['description']?.toString() ?? '';
          item._qtyCtrl.text = _numVal(m['qty']).toString();
          item._priceCtrl.text = _numVal(m['unit_price']).toString();
          _items.add(item);
        }
      }
      if (_partyId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCredit());
      }
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final i in _items) i.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.total);

  double get _availableCredit {
    final avail = (_creditScore?['available_credit'] as num?)?.toDouble() ?? 0;
    // In edit mode, this sale's own current total_amount is already excluded
    // server-side (handled by updateSale) — the banner here is informational,
    // final enforcement always happens on the backend.
    return avail;
  }

  Future<void> _fetchCredit() async {
    if (_partyId == null) return;
    setState(() => _loadingCredit = true);
    try {
      final score = await ref.read(espRepositoryProvider).getCreditScore(_partyType, _partyId!);
      if (mounted) setState(() => _creditScore = score);
    } catch (_) {
      if (mounted) setState(() => _creditScore = null);
    } finally {
      if (mounted) setState(() => _loadingCredit = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _saleDate = picked);
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_espId == null) { _snack('Select a provider'); return; }
    if (_partyId == null) { _snack('Select a ${_partyLabelForType()}'); return; }
    final items = _items.where((i) => i._descCtrl.text.trim().isNotEmpty && i.qty > 0).toList();
    if (items.isEmpty) { _snack('Add at least one item'); return; }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(espRepositoryProvider);
      if (_isEdit) {
        await repo.updateSale(
          (widget.editSale!['id'] as num).toInt(),
          saleDate: _fmtDate(_saleDate),
          notes: _notesCtrl.text.trim(),
          items: items.map((i) => i.toMap()).toList(),
        );
        _snack('Sale updated', error: false);
      } else {
        await repo.createSale(
          espId: _espId!,
          partyType: _partyType,
          partyId: _partyId!,
          saleDate: _fmtDate(_saleDate),
          notes: _notesCtrl.text.trim(),
          items: items.map((i) => i.toMap()).toList(),
        );
        _snack('Sale recorded', error: false);
      }
      if (mounted) context.pop(true);
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg = 'Failed to save sale';
      if (data is Map) msg = data['message']?.toString() ?? msg;
      _snack(msg);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _partyLabelForType() =>
      _partyTypes.firstWhere((t) => t['value'] == _partyType)['label']!;

  void _snack(String msg, {bool error = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? WakulimaColors.error : WakulimaColors.success,
      ));

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(_espProvidersProvider);
    final partiesAsync = ref.watch(_espPartiesProvider(_partyType));

    final providers = providersAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);
    final parties = partiesAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);

    final overLimit = _creditScore != null && _total > _availableCredit;

    if (!_isEdit && _linkedProvider == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
            onPressed: () => context.pop(),
          ),
          title: const Text('New ESP Sale',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: WakulimaColors.gold50, shape: BoxShape.circle),
                child: const Icon(Icons.link_off_rounded, size: 30, color: WakulimaColors.warning),
              ),
              const SizedBox(height: 16),
              const Text('Account not linked to an agrovet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
              const SizedBox(height: 6),
              const Text(
                'Recording ESP sales is only available to accounts linked to an agrovet/service-provider. Ask an admin to link your login.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted),
              ),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
          onPressed: () => context.pop(),
        ),
        title: Text(_isEdit ? 'Edit ESP Sale' : 'New ESP Sale',
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SfSectionLabel('Provider (agrovet / service provider) *'),
              IgnorePointer(
                ignoring: _providerLocked,
                child: Opacity(
                  opacity: _providerLocked ? 0.6 : 1,
                  child: SfSearchField(
                    hint: 'Select provider',
                    selectedValue: _espId?.toString(),
                    items: _linkedProvider != null ? [_linkedProvider!, ...providers] : providers,
                    valueFn: (p) => p['id']?.toString() ?? '',
                    labelFn: (p) => p['name']?.toString() ?? '',
                    subLabelFn: (p) => p['esp_code']?.toString(),
                    pickerTitle: 'Select Provider',
                    onChanged: (p) => setState(() => _espId = (p['id'] as num?)?.toInt()),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              const SfSectionLabel('Bill To *'),
              IgnorePointer(
                ignoring: _isEdit,
                child: Opacity(
                  opacity: _isEdit ? 0.6 : 1,
                  child: Row(
                    children: _partyTypes.map((t) {
                      final selected = _partyType == t['value'];
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _partyType = t['value']!;
                            _partyId = null;
                            _creditScore = null;
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? WakulimaColors.primary700 : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: selected ? WakulimaColors.primary700 : WakulimaColors.border),
                            ),
                            child: Text(t['label']!,
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? Colors.white : WakulimaColors.inkMid)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              IgnorePointer(
                ignoring: _isEdit,
                child: Opacity(
                  opacity: _isEdit ? 0.6 : 1,
                  child: SfSearchField(
                    hint: 'Select ${_partyLabelForType().toLowerCase()}',
                    selectedValue: _partyId?.toString(),
                    items: parties,
                    valueFn: (p) => p['id']?.toString() ?? '',
                    labelFn: (p) => p['full_name']?.toString() ?? p['name']?.toString() ?? '',
                    subLabelFn: (p) => p['farmer_no']?.toString() ?? p['emp_no']?.toString() ?? p['code']?.toString(),
                    searchFn: (p, q) =>
                        (p['full_name'] ?? p['name'] ?? '').toString().toLowerCase().contains(q) ||
                        (p['farmer_no'] ?? p['emp_no'] ?? p['code'] ?? '').toString().toLowerCase().contains(q),
                    pickerTitle: 'Select ${_partyLabelForType()}',
                    onChanged: (p) {
                      setState(() {
                        _partyId = (p['id'] as num?)?.toInt();
                        _creditScore = null;
                      });
                      _fetchCredit();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_partyId != null) _creditBanner(overLimit),
              if (_partyId != null) const SizedBox(height: 12),

              const SfSectionLabel('Sale Date'),
              GestureDetector(
                onTap: _pickDate,
                child: SfInputBox(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(children: [
                    Expanded(child: Text(_fmtDate(_saleDate), style: const TextStyle(fontFamily: 'Poppins', fontSize: 13))),
                    const Icon(Icons.calendar_today_outlined, size: 15, color: WakulimaColors.inkMuted),
                  ]),
                ),
              ),
              const SizedBox(height: 18),

              Row(children: [
                const Text('Items (goods/services sold)',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _items.add(_EspItem())),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Add Item', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: WakulimaColors.primary700),
                ),
              ]),
              const SizedBox(height: 6),

              ...List.generate(_items.length, (i) => _itemRow(i)),

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: WakulimaColors.border)),
                child: Row(children: [
                  const Text('Total', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('KES ${_total.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: overLimit ? WakulimaColors.error : WakulimaColors.primary700)),
                ]),
              ),

              const SizedBox(height: 12),
              const SfSectionLabel('Notes'),
              SfTextField(_notesCtrl, 'Additional notes', maxLines: 2),
              const SizedBox(height: 90),
            ]),
          ),
        ),

        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: WakulimaColors.primary700, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? 'Save Changes' : 'Record Sale  ·  KES ${_total.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _creditBanner(bool overLimit) {
    if (_loadingCredit) {
      return const SizedBox(
          height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: WakulimaColors.primary700)));
    }
    if (_creditScore == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WakulimaColors.gold50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WakulimaColors.gold400.withOpacity(0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: WakulimaColors.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text("Couldn't load credit score — check your connection",
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.warning)),
          ),
          TextButton(
            onPressed: _fetchCredit,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
            child: const Text('Retry', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: WakulimaColors.warning)),
          ),
        ]),
      );
    }
    final avail = (_creditScore!['available_credit'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overLimit ? const Color(0xFFFFF3F3) : WakulimaColors.primary50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: overLimit ? WakulimaColors.error : WakulimaColors.primary200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(overLimit ? Icons.warning_amber_rounded : Icons.verified_outlined,
              size: 16, color: overLimit ? WakulimaColors.error : WakulimaColors.primary700),
          const SizedBox(width: 6),
          Text('Available credit: KES ${avail.toStringAsFixed(2)}',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: overLimit ? WakulimaColors.error : WakulimaColors.primary700)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Gross value: KES ${((_creditScore!['gross_value'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
          '  ·  Already invoiced: KES ${((_creditScore!['already_invoiced'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
          '  ·  Debts: KES ${((_creditScore!['current_debts'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: WakulimaColors.inkMuted),
        ),
        if (overLimit)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('This sale exceeds available credit and will be rejected on submit.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.error)),
          ),
      ]),
    );
  }

  Widget _itemRow(int index) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: SfTextField(item._descCtrl, 'Item / service description')),
          if (_items.length > 1)
            GestureDetector(
              onTap: () => setState(() => _items.removeAt(index)),
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 18, color: WakulimaColors.error),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _labeledNumberField('Qty', item._qtyCtrl)),
          const SizedBox(width: 8),
          Expanded(child: _labeledNumberField('Unit Price', item._priceCtrl)),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text('KES ${item.total.toStringAsFixed(2)}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
        ),
      ]),
    );
  }

  Widget _labeledNumberField(String label, TextEditingController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: WakulimaColors.inkMuted)),
      const SizedBox(height: 3),
      SfInputBox(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
        ),
      ),
    ]);
  }
}

final _espProvidersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    return await ref.watch(espRepositoryProvider).getProviders();
  } catch (_) {
    return [];
  }
});

final _espPartiesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, partyType) async {
  try {
    return await ref.watch(espRepositoryProvider).getParties(partyType);
  } catch (_) {
    return [];
  }
});
