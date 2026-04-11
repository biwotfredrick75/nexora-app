import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/widgets/module_scaffold.dart';

// ── Providers ──────────────────────────────────────────────────────────────────

final _paymentFormDataProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ApiClient();
  try {
    final res = await api.get('/farmers/supplier-payments/form-data');
    final body = res.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'] as Map<String, dynamic>;
  } catch (_) {}
  return {};
});

// ── Screen ─────────────────────────────────────────────────────────────────────

class PaymentToFarmersScreen extends ConsumerStatefulWidget {
  const PaymentToFarmersScreen({super.key});
  @override
  ConsumerState<PaymentToFarmersScreen> createState() => _State();
}

class _State extends ConsumerState<PaymentToFarmersScreen> {
  final _refCtrl    = TextEditingController();
  final _discCtrl   = TextEditingController(text: '0.00');
  final _amtCtrl    = TextEditingController();
  final _chargeCtrl = TextEditingController(text: '0.00');
  final _chequeCtrl = TextEditingController();
  final _memoCtrl   = TextEditingController();

  int?    _farmerId;
  String? _fromAccount;
  DateTime _datePaid = DateTime.now();
  String  _type = 'payment';
  int?    _withholdingTaxId;
  double  _withholdingRate = 0;

  bool _submitting = false;

  @override
  void dispose() {
    _refCtrl.dispose(); _discCtrl.dispose(); _amtCtrl.dispose();
    _chargeCtrl.dispose(); _chequeCtrl.dispose(); _memoCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datePaid,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _datePaid = picked);
  }

  Future<void> _submit(List farmers, List taxes) async {
    if (_farmerId == null) { _snack('Select farmer'); return; }
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    if (amt <= 0) { _snack('Enter payment amount'); return; }

    setState(() => _submitting = true);
    try {
      final api = ApiClient();
      await api.post('/farmers/supplier-payments', data: {
        'farmer_id':            _farmerId,
        'from_account':         _fromAccount,
        'date_paid':            _fmtDate(_datePaid),
        'reference':            _refCtrl.text.trim(),
        'type':                 _type,
        'withholding_tax_rate': _withholdingRate,
        'amount_discount':      double.tryParse(_discCtrl.text) ?? 0,
        'amount_payment':       amt,
        'bank_charge':          double.tryParse(_chargeCtrl.text) ?? 0,
        'cheque_no':            _chequeCtrl.text.trim(),
        'memo':                 _memoCtrl.text.trim(),
      });
      if (!mounted) return;
      _snack('Payment recorded', error: false);
      _reset();
    } catch (e) {
      _snack('Failed: ${e.toString().split(':').last.trim()}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    setState(() {
      _farmerId = null; _fromAccount = null;
      _datePaid = DateTime.now(); _type = 'payment';
      _withholdingTaxId = null; _withholdingRate = 0;
    });
    _refCtrl.clear(); _discCtrl.text = '0.00'; _amtCtrl.clear();
    _chargeCtrl.text = '0.00'; _chequeCtrl.clear(); _memoCtrl.clear();
  }

  void _snack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? WakulimaColors.error : WakulimaColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final formAsync = ref.watch(_paymentFormDataProvider);
    return ModuleScaffold(
      title: 'Payment to Farmers',
      color: WakulimaColors.dairyAdmin,
      icon: Icons.payments_outlined,
      body: formAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (_, __) => const Center(child: Text('Failed to load form data')),
        data:    (data) {
          final farmers  = (data['farmers']  as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final taxes    = (data['withholdingTaxes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final accounts = (data['bankAccounts'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          return _buildForm(farmers, taxes, accounts);
        },
      ),
    );
  }

  Widget _buildForm(List<Map<String,dynamic>> farmers, List<Map<String,dynamic>> taxes, List<Map<String,dynamic>> accounts) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _card([
          _row('Payment To', _searchFarmerDropdown(farmers)),
          _row('From Bank Account', _dropdown(
            value: _fromAccount,
            hint: 'Select account',
            items: accounts.map((a) => DropdownMenuItem(
              value: a['account_code']?.toString(),
              child: Text(a['account_name']?.toString() ?? '', style: _ts),
            )).toList(),
            onChanged: (v) => setState(() => _fromAccount = v),
          )),
          _row('Date Paid', GestureDetector(
            onTap: _pickDate,
            child: _inputBox(Row(children: [
              Text(_fmtDate(_datePaid), style: _ts),
              const Spacer(),
              Icon(Icons.calendar_today_outlined, size: 16, color: WakulimaColors.inkMuted),
            ])),
          )),
          _row('Reference', _textField(_refCtrl, '001/2026')),
          _row('Type', _dropdown(
            value: _type,
            hint: 'Select type',
            items: const [
              DropdownMenuItem(value: 'payment', child: Text('Payment')),
              DropdownMenuItem(value: 'advance',  child: Text('Advance')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'payment'),
          )),
          _row('Bank Charge', Row(children: [
            Expanded(child: _textField(_chargeCtrl, '0.00', numeric: true)),
            const SizedBox(width: 8),
            const Text('KES', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted)),
          ])),
        ]),
        const SizedBox(height: 12),
        _card([
          _tableRow('Withholding Tax Rate', _dropdown(
            value: _withholdingTaxId?.toString(),
            hint: '- None -',
            items: taxes.map((t) => DropdownMenuItem(
              value: t['id'].toString(),
              child: Text('${t['description']} (${t['rate']}%)', style: _ts),
            )).toList(),
            onChanged: (v) {
              if (v == null) { setState(() { _withholdingTaxId = null; _withholdingRate = 0; }); return; }
              final tax = taxes.firstWhere((t) => t['id'].toString() == v, orElse: () => {});
              setState(() {
                _withholdingTaxId = int.tryParse(v);
                _withholdingRate  = (tax['rate'] as num?)?.toDouble() ?? 0;
              });
            },
          )),
          _tableRow('Amount of Discount', Row(children: [
            Expanded(child: _textField(_discCtrl, '0.00', numeric: true)),
            const SizedBox(width: 8),
            const Text('KES', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted)),
          ])),
          _tableRow('Amount of Payment', Row(children: [
            Expanded(child: _textField(_amtCtrl, '', numeric: true)),
            const SizedBox(width: 8),
            const Text('KES', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted)),
          ])),
          _tableRow('Cheque No', _textField(_chequeCtrl, '')),
          _tableRow('Memo', TextField(
            controller: _memoCtrl,
            maxLines: 3,
            style: _ts,
            decoration: InputDecoration(
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: WakulimaColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: WakulimaColors.border)),
            ),
          )),
        ]),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _submitting ? null : () => _submit(farmers, taxes),
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, color: Colors.white),
          label: Text(_submitting ? 'Processing...' : 'Enter Payment',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: WakulimaColors.dairyAdmin,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        )),
      ]),
    );
  }

  Widget _searchFarmerDropdown(List<Map<String,dynamic>> farmers) {
    final selected = farmers.firstWhere((f) => f['id'] == _farmerId, orElse: () => {});
    return GestureDetector(
      onTap: () => _showFarmerSearch(farmers),
      child: _inputBox(Row(children: [
        Expanded(child: Text(
          selected.isEmpty ? 'Select farmer...' : selected['full_name']?.toString() ?? '',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
            color: selected.isEmpty ? WakulimaColors.inkMuted : WakulimaColors.ink),
        )),
        const Icon(Icons.arrow_drop_down, color: WakulimaColors.inkMuted),
      ])),
    );
  }

  void _showFarmerSearch(List<Map<String,dynamic>> farmers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FarmerSearchSheet(
        farmers: farmers,
        onSelected: (id) => setState(() => _farmerId = id),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: WakulimaColors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: WakulimaColors.border),
    ),
    child: Column(children: children),
  );

  Widget _row(String label, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMid))),
      Expanded(child: child),
    ]),
  );

  Widget _tableRow(String label, Widget child) => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMid)),
        )),
        Expanded(child: child),
      ]),
    ),
    const Divider(height: 1, color: WakulimaColors.border),
  ]);

  Widget _inputBox(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: WakulimaColors.white, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: WakulimaColors.border),
    ),
    child: child,
  );

  Widget _textField(TextEditingController ctrl, String hint, {bool numeric = false}) => TextField(
    controller: ctrl,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    style: _ts,
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.inkMuted),
      filled: true, fillColor: WakulimaColors.white, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: WakulimaColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: WakulimaColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: WakulimaColors.dairyAdmin, width: 1.5)),
    ),
  );

  Widget _dropdown({required String? value, required String hint, required List<DropdownMenuItem<String>> items, required ValueChanged<String?> onChanged}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: WakulimaColors.white, borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: value, hint: Text(hint, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.inkMuted)),
        isExpanded: true, items: items, onChanged: onChanged,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.ink),
      )),
    );

  static const TextStyle _ts = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.ink);
}

// ── Farmer search bottom sheet ─────────────────────────────────────────────────

class _FarmerSearchSheet extends StatefulWidget {
  final List<Map<String,dynamic>> farmers;
  final ValueChanged<int> onSelected;
  const _FarmerSearchSheet({required this.farmers, required this.onSelected});
  @override
  State<_FarmerSearchSheet> createState() => _FarmerSearchSheetState();
}

class _FarmerSearchSheetState extends State<_FarmerSearchSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.farmers
        : widget.farmers.where((f) =>
            (f['full_name'] ?? '').toString().toLowerCase().contains(_q.toLowerCase()) ||
            (f['farmer_no'] ?? '').toString().toLowerCase().contains(_q.toLowerCase())).toList();

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: WakulimaColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          const Text('Select Farmer', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by name or code…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true, fillColor: WakulimaColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: WakulimaColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: WakulimaColors.border)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: filtered.isEmpty
              ? const Center(child: Text('No farmers found', style: TextStyle(fontFamily: 'Poppins', color: WakulimaColors.inkMuted)))
              : ListView.separated(
                  controller: ctrl,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(f['full_name']?.toString() ?? '', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: Text(f['farmer_no']?.toString() ?? '', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkMuted)),
                      onTap: () {
                        widget.onSelected((f['id'] as num).toInt());
                        Navigator.pop(context);
                      },
                    );
                  },
                )),
        ]),
      ),
    );
  }
}
