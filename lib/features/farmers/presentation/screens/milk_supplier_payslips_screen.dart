import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakulima/core/network/api_client.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/widgets/module_scaffold.dart';

// ── Providers ──────────────────────────────────────────────────────────────────

final _formDataProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiClient().get('/farmers/milk-payslips/form-data');
  final body = res.data as Map<String, dynamic>;
  if (body['success'] == true) return body['data'] as Map<String, dynamic>;
  return {};
});

// ── Screen ─────────────────────────────────────────────────────────────────────

class MilkSupplierPayslipsScreen extends ConsumerStatefulWidget {
  const MilkSupplierPayslipsScreen({super.key});
  @override
  ConsumerState<MilkSupplierPayslipsScreen> createState() => _State();
}

class _State extends ConsumerState<MilkSupplierPayslipsScreen> {
  static const _color = WakulimaColors.dairyAdmin;

  String _filterType = 'route';
  int?    _routeId;
  int?    _farmerId;
  int     _month = DateTime.now().month;
  int     _year  = DateTime.now().year;

  bool _loading = false;
  List<Map<String, dynamic>> _payslips = [];
  bool _hasFetched = false;

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  String _fmt(double v) => v.toStringAsFixed(2);

  Future<void> _fetch() async {
    if (_filterType == 'route' && _routeId == null) {
      _snack('Select a route'); return;
    }
    if (_filterType == 'individual' && _farmerId == null) {
      _snack('Select a farmer'); return;
    }
    setState(() { _loading = true; _hasFetched = false; });
    try {
      final params = <String, dynamic>{
        'filter_type': _filterType,
        'month': _month,
        'year': _year,
        if (_filterType == 'route' && _routeId != null) 'route_id': _routeId,
        if (_filterType == 'individual' && _farmerId != null) 'farmer_id': _farmerId,
      };
      final res  = await ApiClient().get('/farmers/milk-payslips', params: params);
      final body = res.data as Map<String, dynamic>;
      if (body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        setState(() {
          _payslips = (data['payslips'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _hasFetched = true;
        });
      }
    } catch (e) {
      _snack('Failed: ${e.toString().split(':').last.trim()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? WakulimaColors.error : WakulimaColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final formAsync = ref.watch(_formDataProvider);
    return ModuleScaffold(
      title: 'Milk Supplier Payslips',
      color: _color,
      icon: Icons.receipt_long_outlined,
      body: formAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (_, __) => const Center(child: Text('Failed to load form data')),
        data:    (data) {
          final routes  = (data['routes']  as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final years   = (data['years']   as List? ?? []).cast<int>();
          final farmers = (data['farmers'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          return _buildBody(routes, years, farmers);
        },
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> routes,
    List<int> years,
    List<Map<String, dynamic>> farmers,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _filterCard(routes, years, farmers),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (_hasFetched && _payslips.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.inbox_outlined, size: 48, color: WakulimaColors.inkMuted),
              const SizedBox(height: 8),
              const Text('No payslip data found',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: WakulimaColors.inkMuted)),
            ]),
          ))
        else
          ..._payslips.map((p) => _PayslipCard(payslip: p, color: _color)),
      ],
    );
  }

  Widget _filterCard(
    List<Map<String, dynamic>> routes,
    List<int> years,
    List<Map<String, dynamic>> farmers,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WakulimaColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Filters', style: TextStyle(
          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
        const SizedBox(height: 12),

        // Filter type toggle
        Row(children: [
          _typeChip('By Route',      'route'),
          const SizedBox(width: 8),
          _typeChip('By Farmer',     'individual'),
        ]),
        const SizedBox(height: 12),

        // Location (route) filter
        if (_filterType == 'route') ...[
          _label('Location / Route'),
          const SizedBox(height: 4),
          _dropdown(
            value: _routeId?.toString(),
            hint: 'Select route…',
            items: routes.map((r) => DropdownMenuItem(
              value: r['id'].toString(),
              child: Text('${r['route_code']} – ${r['route_name']}', style: _ts),
            )).toList(),
            onChanged: (v) => setState(() => _routeId = v == null ? null : int.tryParse(v)),
          ),
        ] else ...[
          _label('Farmer'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _showFarmerSearch(farmers),
            child: _inputBox(Row(children: [
              Expanded(child: Text(
                _farmerId == null
                    ? 'Select farmer…'
                    : (farmers.firstWhere((f) => f['id'] == _farmerId, orElse: () => {})['full_name'] ?? ''),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: _farmerId == null ? WakulimaColors.inkMuted : WakulimaColors.ink),
              )),
              const Icon(Icons.arrow_drop_down, color: WakulimaColors.inkMuted),
            ])),
          ),
        ],
        const SizedBox(height: 12),

        // Month and Year row
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Month'),
            const SizedBox(height: 4),
            _dropdown(
              value: _month.toString(),
              hint: 'Month',
              items: List.generate(12, (i) => DropdownMenuItem(
                value: (i + 1).toString(),
                child: Text(_months[i], style: _ts),
              )),
              onChanged: (v) => setState(() => _month = int.parse(v!)),
            ),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Year'),
            const SizedBox(height: 4),
            _dropdown(
              value: _year.toString(),
              hint: 'Year',
              items: years.map((y) => DropdownMenuItem(
                value: y.toString(),
                child: Text(y.toString(), style: _ts),
              )).toList(),
              onChanged: (v) => setState(() => _year = int.parse(v!)),
            ),
          ])),
        ]),
        const SizedBox(height: 16),

        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _loading ? null : _fetch,
          icon: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search, color: Colors.white, size: 18),
          label: Text(_loading ? 'Generating…' : 'Generate Payslips',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _color,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        )),
      ]),
    );
  }

  Widget _typeChip(String label, String value) {
    final sel = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() {
        _filterType = value;
        _routeId = null;
        _farmerId = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _color : WakulimaColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _color : WakulimaColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500,
          color: sel ? Colors.white : WakulimaColors.inkSoft)),
      ),
    );
  }

  void _showFarmerSearch(List<Map<String, dynamic>> farmers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FarmerSearchSheet(
        farmers: farmers,
        onSelected: (id) => setState(() => _farmerId = id),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(
    fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500, color: WakulimaColors.inkMuted));

  Widget _inputBox(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: WakulimaColors.white, borderRadius: BorderRadius.circular(8),
      border: Border.all(color: WakulimaColors.border),
    ),
    child: child,
  );

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: WakulimaColors.white, borderRadius: BorderRadius.circular(8),
      border: Border.all(color: WakulimaColors.border),
    ),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value,
      hint: Text(hint, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.inkMuted)),
      isExpanded: true, items: items, onChanged: onChanged,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.ink),
    )),
  );

  static const TextStyle _ts = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.ink);
}

// ── Payslip card ───────────────────────────────────────────────────────────────

class _PayslipCard extends StatelessWidget {
  final Map<String, dynamic> payslip;
  final Color color;
  const _PayslipCard({required this.payslip, required this.color});

  String _fmt(num v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final farmer   = Map<String, dynamic>.from(payslip['farmer'] as Map);
    final rows     = (payslip['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final totals   = Map<String, dynamic>.from(payslip['totals'] as Map);
    final deducts  = (payslip['deductions'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList();
    final totalDed = (payslip['total_deductions'] as num).toDouble();
    final netPay   = (payslip['net_pay'] as num).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: WakulimaColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.person_outline, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(farmer['full_name']?.toString() ?? '', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              Text('${farmer['farmer_no'] ?? ''} · ${farmer['route_name'] ?? ''}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkMuted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Net Pay', style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10, color: WakulimaColors.inkMuted)),
              Text('KES ${_fmt(netPay)}', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: color)),
            ]),
          ]),
        ),

        // Daily table
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Milk Collection', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
            const SizedBox(height: 8),
            _tableHeader(),
            ...rows.where((r) => (r['total'] as num) > 0).map((r) => _tableRow(r)),
            _tableTotalsRow(totals),
          ]),
        ),

        // Deductions
        if (deducts.isNotEmpty) ...[
          const Divider(height: 24, color: WakulimaColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Deductions', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
              const SizedBox(height: 6),
              ...deducts.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: Text(d['label']?.toString() ?? '', style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkSoft))),
                  Text('KES ${_fmt((d['amount'] as num).toDouble())}', style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.error)),
                ]),
              )),
            ]),
          ),
        ],

        // Summary footer
        const Divider(height: 24, color: WakulimaColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(children: [
            _summaryRow('Total Milk Value', 'KES ${_fmt((totals['amount'] as num).toDouble())}', bold: false),
            if (deducts.isNotEmpty)
              _summaryRow('Total Deductions', '- KES ${_fmt(totalDed)}',
                valueColor: WakulimaColors.error, bold: false),
            const Divider(height: 12, color: WakulimaColors.border),
            _summaryRow('NET PAY', 'KES ${_fmt(netPay)}', valueColor: color, bold: true),
          ]),
        ),
      ]),
    );
  }

  Widget _tableHeader() => Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    decoration: BoxDecoration(
      color: WakulimaColors.surface, borderRadius: BorderRadius.circular(6)),
    child: Row(children: const [
      SizedBox(width: 80, child: Text('Date', style: _headerStyle)),
      Expanded(child: Text('AM', style: _headerStyle, textAlign: TextAlign.right)),
      Expanded(child: Text('PM', style: _headerStyle, textAlign: TextAlign.right)),
      Expanded(child: Text('Total', style: _headerStyle, textAlign: TextAlign.right)),
      Expanded(child: Text('Amount', style: _headerStyle, textAlign: TextAlign.right)),
    ]),
  );

  Widget _tableRow(Map<String, dynamic> r) {
    final date = r['date']?.toString() ?? '';
    final label = date.length >= 10 ? date.substring(5, 10) : date;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: _cellStyle)),
        Expanded(child: Text(_fmt((r['morning'] as num).toDouble()), style: _cellStyle, textAlign: TextAlign.right)),
        Expanded(child: Text(_fmt((r['evening'] as num).toDouble()), style: _cellStyle, textAlign: TextAlign.right)),
        Expanded(child: Text(_fmt((r['total'] as num).toDouble()), style: _cellStyle, textAlign: TextAlign.right)),
        Expanded(child: Text(_fmt((r['amount'] as num).toDouble()), style: _cellStyle, textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _tableTotalsRow(Map<String, dynamic> t) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    decoration: BoxDecoration(
      color: WakulimaColors.surface, borderRadius: BorderRadius.circular(6)),
    child: Row(children: [
      const SizedBox(width: 80, child: Text('TOTAL', style: _totalStyle)),
      Expanded(child: Text(_fmt((t['morning'] as num).toDouble()), style: _totalStyle, textAlign: TextAlign.right)),
      Expanded(child: Text(_fmt((t['evening'] as num).toDouble()), style: _totalStyle, textAlign: TextAlign.right)),
      Expanded(child: Text(_fmt((t['qty'] as num).toDouble()), style: _totalStyle, textAlign: TextAlign.right)),
      Expanded(child: Text(_fmt((t['amount'] as num).toDouble()), style: _totalStyle, textAlign: TextAlign.right)),
    ]),
  );

  Widget _summaryRow(String label, String value, {Color? valueColor, bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(
        fontFamily: 'Poppins', fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: WakulimaColors.inkSoft))),
      Text(value, style: TextStyle(
        fontFamily: 'Poppins', fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: valueColor ?? WakulimaColors.ink)),
    ]),
  );

  static const TextStyle _headerStyle = TextStyle(
    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: WakulimaColors.inkMuted);
  static const TextStyle _cellStyle = TextStyle(
    fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkSoft);
  static const TextStyle _totalStyle = TextStyle(
    fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: WakulimaColors.ink);
}

// ── Farmer search bottom sheet ─────────────────────────────────────────────────

class _FarmerSearchSheet extends StatefulWidget {
  final List<Map<String, dynamic>> farmers;
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
          const Text('Select Farmer', style: TextStyle(
            fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: WakulimaColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: WakulimaColors.border)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: filtered.isEmpty
              ? const Center(child: Text('No farmers found',
                  style: TextStyle(fontFamily: 'Poppins', color: WakulimaColors.inkMuted)))
              : ListView.separated(
                  controller: ctrl,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(f['full_name']?.toString() ?? '',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: Text('${f['farmer_no'] ?? ''} · ${f['route_name'] ?? ''}',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkMuted)),
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
