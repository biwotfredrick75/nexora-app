import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _ReturnCartItem {
  final String stockId;
  final String description;
  final double qty;
  final double price;
  final double discountPct;
  final String unit;
  final double standardCost;
  final String? batchNo;

  _ReturnCartItem({
    required this.stockId,
    required this.description,
    required this.qty,
    required this.price,
    required this.discountPct,
    required this.unit,
    required this.standardCost,
    this.batchNo,
  });

  double get lineTotal => qty * price;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _returnCustomersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api
        .get('/sales/customers', params: {'per_page': '300'})
        .timeout(const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  } catch (_) { return []; }
});

final _returnsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final now = DateTime.now();
  final from = DateFormat('yyyy-MM-01').format(now);
  final to   = DateFormat('yyyy-MM-dd').format(now);
  try {
    final res = await api
        .get('/sales/credit-notes',
            params: {'date_from': from, 'date_to': to, 'per_page': '100'})
        .timeout(const Duration(seconds: 12));
    final body = res.data as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final data = body['data'];
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  } catch (_) { return []; }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ReturnItemScreen extends ConsumerStatefulWidget {
  const ReturnItemScreen({super.key});
  @override
  ConsumerState<ReturnItemScreen> createState() => _ReturnItemScreenState();
}

class _ReturnItemScreenState extends ConsumerState<ReturnItemScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // ── Selection state ──────────────────────────────────────────────────────
  Map<String, dynamic>? _customer;
  Map<String, dynamic>? _invoice;
  Map<String, dynamic>? _item;

  // ── Invoices & items for selected customer/invoice ───────────────────────
  List<Map<String, dynamic>> _invoices    = [];
  List<Map<String, dynamic>> _returnItems = [];

  bool _loadingInvoices = false;
  bool _loadingItems    = false;

  // ── Form inputs ──────────────────────────────────────────────────────────
  final _qtyCtrl   = TextEditingController();
  final _batchCtrl = TextEditingController();
  DateTime _returnDate = DateTime.now();

  // ── Cart ─────────────────────────────────────────────────────────────────
  final List<_ReturnCartItem> _cart = [];

  // ── Return type ──────────────────────────────────────────────────────────
  String _returnType = 'return_to_store';

  // ── Submission ───────────────────────────────────────────────────────────
  bool _submitting = false;

  // ── Formatters ────────────────────────────────────────────────────────────
  final _nf = NumberFormat('#,##0.00', 'en_KE');

  String get _fmtDate =>
      DateFormat('yyyy-MM-dd').format(_returnDate);

  String _kes(double v) => 'KES ${_nf.format(v)}';

  double get _maxQty =>
      (_item?['returnable_qty'] as num?)?.toDouble() ?? 0;

  double get _enteredQty => double.tryParse(_qtyCtrl.text) ?? 0;

  double get _unitPrice => (_item?['price'] as num?)?.toDouble() ?? 0;

  double get _discPct => (_item?['discount_pct'] as num?)?.toDouble() ?? 0;

  double get _returnValue =>
      _enteredQty > 0 ? _enteredQty * _unitPrice : 0;

  double get _cartTotal =>
      _cart.fold(0, (s, r) => s + r.lineTotal);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _qtyCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadInvoices(String debtorNo) async {
    setState(() { _loadingInvoices = true; _invoices = []; _invoice = null; _item = null; _returnItems = []; });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api
          .get('/sales/invoices', params: {'debtor_no': debtorNo, 'status': 'placed', 'per_page': '200'})
          .timeout(const Duration(seconds: 12));
      final body = res.data as Map<String, dynamic>;
      final data = body['data'];
      List<Map<String, dynamic>> list = [];
      if (data is List) list = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (data is Map && data['data'] is List) list = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() => _invoices = list);
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingInvoices = false);
    }
  }

  Future<void> _loadReturnableItems(int invId) async {
    setState(() { _loadingItems = true; _returnItems = []; _item = null; });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api
          .get('/sales/invoices/$invId/returnable-items')
          .timeout(const Duration(seconds: 12));
      final body = res.data as Map<String, dynamic>;
      final items = body['data']?['items'] as List? ?? [];
      setState(() => _returnItems = items
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((item) => ((item['price'] as num?)?.toDouble() ?? 0) > 0)
          .toList());
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  // ── Pickers (bottom sheets) ────────────────────────────────────────────────

  Future<void> _pickCustomer(List<Map<String, dynamic>> customers) async {
    final picked = await _showSearchSheet<Map<String, dynamic>>(
      title: 'Select Customer',
      items: customers,
      labelFn: (c) => '${c['name'] ?? ''} - ${c['debtor_no'] ?? ''}',
      searchFn: (c, q) =>
          (c['name']?.toString() ?? '').toLowerCase().contains(q) ||
          (c['debtor_no']?.toString() ?? '').toLowerCase().contains(q),
    );
    if (picked == null) return;
    setState(() { _customer = picked; _invoice = null; _item = null; _cart.clear(); });
    _loadInvoices(picked['debtor_no'].toString());
  }

  Future<void> _pickInvoice() async {
    if (_invoices.isEmpty) return;
    final picked = await _showSearchSheet<Map<String, dynamic>>(
      title: 'Select Invoice',
      items: _invoices,
      labelFn: (i) => '#${i['id']} (${i['inv_no'] ?? ''})',
      searchFn: (i, q) =>
          (i['inv_no']?.toString() ?? '').toLowerCase().contains(q) ||
          (i['id']?.toString() ?? '').contains(q),
    );
    if (picked == null) return;
    setState(() { _invoice = picked; _item = null; _cart.clear(); });
    _loadReturnableItems((picked['id'] as num).toInt());
  }

  Future<void> _pickItem() async {
    if (_returnItems.isEmpty) return;
    final picked = await _showSearchSheet<Map<String, dynamic>>(
      title: 'Select Item',
      items: _returnItems,
      labelFn: (i) => '${i['description'] ?? i['stock_id']}',
      searchFn: (i, q) =>
          (i['description']?.toString() ?? '').toLowerCase().contains(q) ||
          (i['stock_id']?.toString() ?? '').toLowerCase().contains(q),
    );
    if (picked == null) return;
    setState(() {
      _item = picked;
      _qtyCtrl.clear();
      _batchCtrl.clear();
    });
  }

  Future<T?> _showSearchSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T) labelFn,
    required bool Function(T, String) searchFn,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _SearchSheet<T>(
        title: title, items: items, labelFn: labelFn, searchFn: searchFn,
      ),
    );
  }

  // ── Cart operations ────────────────────────────────────────────────────────

  void _addToCart() {
    if (_item == null) { _snack('Select an item'); return; }
    final qty = _enteredQty;
    if (qty <= 0) { _snack('Enter a return quantity'); return; }
    if (qty > _maxQty) { _snack('Qty exceeds max returnable (${_nf.format(_maxQty)})'); return; }
    final itemPrice = (_item!['price'] as num?)?.toDouble() ?? 0;
    if (itemPrice <= 0) {
      _snack(
        'No selling price found for "${_item!['description'] ?? _item!['stock_id']}". '
        'Please set a selling price before processing this return.',
        error: true,
      );
      return;
    }

    // Check duplicate — merge if same stock_id
    final existingIdx = _cart.indexWhere((r) => r.stockId == _item!['stock_id']);
    if (existingIdx >= 0) {
      final existing = _cart[existingIdx];
      final newQty = existing.qty + qty;
      if (newQty > _maxQty) { _snack('Total would exceed max (${_nf.format(_maxQty)})'); return; }
      _cart[existingIdx] = _ReturnCartItem(
        stockId: existing.stockId, description: existing.description,
        qty: newQty, price: existing.price, discountPct: existing.discountPct,
        unit: existing.unit, standardCost: existing.standardCost,
        batchNo: _batchCtrl.text.trim().isEmpty ? existing.batchNo : _batchCtrl.text.trim(),
      );
    } else {
      _cart.add(_ReturnCartItem(
        stockId: _item!['stock_id'].toString(),
        description: _item!['description']?.toString() ?? _item!['stock_id'].toString(),
        qty: qty,
        price: (_item!['price'] as num?)?.toDouble() ?? 0,
        discountPct: (_item!['discount_pct'] as num?)?.toDouble() ?? 0,
        unit: _item!['unit']?.toString() ?? '',
        standardCost: (_item!['standard_cost'] as num?)?.toDouble() ?? 0,
        batchNo: _batchCtrl.text.trim().isEmpty ? null : _batchCtrl.text.trim(),
      ));
    }

    setState(() {
      _item = null;
      _qtyCtrl.clear();
      _batchCtrl.clear();
    });
    _snack('Added to return cart', error: false);
  }

  void _removeFromCart(int idx) {
    setState(() => _cart.removeAt(idx));
  }

  // ── Process return ─────────────────────────────────────────────────────────

  Future<void> _processReturn() async {
    if (_cart.isEmpty) { _snack('Add items to the return cart first'); return; }
    if (_customer == null) { _snack('Select a customer'); return; }

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);

      // 1. Create draft credit note
      final cnRes = await api.post('/sales/credit-notes', data: {
        'cn_type':   _returnType,
        'inv_id':    _invoice?['id'],
        'debtor_no': _customer!['debtor_no'],
        'cn_date':   _fmtDate,
        'items': _cart.map((r) => {
          'stock_id':      r.stockId,
          'description':   r.description,
          'qty':           r.qty,
          'price':         r.price,
          'discount_pct':  r.discountPct,
          'unit':          r.unit.isEmpty ? null : r.unit,
          'standard_cost': r.standardCost,
        }).toList(),
      }).timeout(const Duration(seconds: 20));

      final cnBody = cnRes.data as Map<String, dynamic>;
      if (cnBody['success'] != true) {
        _snack(cnBody['message']?.toString() ?? 'Failed to create return');
        return;
      }

      final cnId = (cnBody['data'] as Map?)?['id'];
      if (cnId == null) { _snack('Could not get credit note ID'); return; }

      // 2. Place the credit note (creates GL + stock movement)
      final placeRes = await api
          .post('/sales/credit-notes/$cnId/place')
          .timeout(const Duration(seconds: 20));

      final placeBody = placeRes.data as Map<String, dynamic>;
      if (placeBody['success'] != true) {
        _snack(placeBody['message']?.toString() ?? 'Failed to place return');
        return;
      }

      final cnNo = (cnBody['data'] as Map?)?['cn_no']?.toString() ?? 'CN-$cnId';
      ref.invalidate(_returnsProvider);
      setState(() {
        _cart.clear();
        _customer = null;
        _invoice  = null;
        _item     = null;
        _invoices    = [];
        _returnItems = [];
        _qtyCtrl.clear();
        _batchCtrl.clear();
        _tabs.animateTo(1); // switch to history tab
      });
      final typeLabel = _returnTypeLabel(_returnType);
      _snack('$typeLabel $cnNo processed successfully.', error: false);
    } catch (e) {
      _snack('Error: ${e.toString().replaceAll('DioException', 'Network error')}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Return type helpers ────────────────────────────────────────────────────

  static const _returnTypes = [
    ('return_to_store', 'Return to Store'),
    ('damage',          'Damage'),
    ('discount',        'Discount'),
    ('write_off',       'Written Off'),
  ];

  static String _returnTypeLabel(String type) => switch (type) {
    'return_to_store' => 'Return to Store',
    'damage'          => 'Damage',
    'discount'        => 'Discount',
    'write_off'       => 'Written Off',
    _                 => type,
  };

  static String _returnTypeInfo(String type) => switch (type) {
    'return_to_store' => 'Goods go back into store inventory. Revenue and cost of goods both reversed. Customer balance reduced.',
    'damage'          => 'Goods moved to damage location (not saleable). Revenue reversed but cost not recovered. Customer balance reduced.',
    'discount'        => 'No stock movement. Revenue reduced by credit amount. Use for pricing errors or goodwill adjustments. Customer balance reduced.',
    'write_off'       => 'No stock movement. Amount recorded as bad debt expense. Use for unrecoverable balances. Customer balance cleared.',
    _                 => '',
  };

  static IconData _returnTypeIcon(String type) => switch (type) {
    'return_to_store' => Icons.store_outlined,
    'damage'          => Icons.warning_amber_outlined,
    'discount'        => Icons.local_offer_outlined,
    'write_off'       => Icons.remove_circle_outline,
    _                 => Icons.keyboard_return_outlined,
  };

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: WakulimaColors.primary50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WakulimaColors.primary200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _returnType,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: WakulimaColors.inkMuted),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w500, color: WakulimaColors.ink),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(10),
          onChanged: (v) { if (v != null) setState(() => _returnType = v); },
          items: _returnTypes.map(((String, String) t) {
            return DropdownMenuItem<String>(
              value: t.$1,
              child: Row(children: [
                Icon(_returnTypeIcon(t.$1), size: 16, color: WakulimaColors.primary700),
                const SizedBox(width: 10),
                Text(t.$2),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTypeBanner() {
    final info = _returnTypeInfo(_returnType);
    final icon = _returnTypeIcon(_returnType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WakulimaColors.primary50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WakulimaColors.primary200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: WakulimaColors.primary700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(info,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.primary700)),
        ),
      ]),
    );
  }

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      backgroundColor: error ? WakulimaColors.error : WakulimaColors.success,
      duration: Duration(seconds: error ? 4 : 2),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(_returnCustomersProvider);
    final returnsAsync   = ref.watch(_returnsProvider);
    final customers = customersAsync.maybeWhen(data: (d) => d, orElse: () => <Map<String, dynamic>>[]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
          onPressed: () => context.pop(),
        ),
        title: const Text('Return Items',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          labelColor: WakulimaColors.primary700,
          unselectedLabelColor: WakulimaColors.inkMuted,
          indicatorColor: WakulimaColors.primary700,
          tabs: const [Tab(text: 'New Return'), Tab(text: 'History')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Tab 0: New Return form (with fixed process button) ─────────
          _buildReturnTab(customers),
          // ── Tab 1: History ─────────────────────────────────────────────
          _buildHistory(returnsAsync),
        ],
      ),
    );
  }

  // ── New Return form ────────────────────────────────────────────────────────

  Widget _buildReturnForm(List<Map<String, dynamic>> customers) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Return Type ───────────────────────────────────────────────────
        _sectionLabel('Return Type'),
        _buildTypeSelector(),
        const SizedBox(height: 6),
        _buildTypeBanner(),
        const SizedBox(height: 16),

        // ── Customer ──────────────────────────────────────────────────────
        _sectionLabel('Customer'),
        _pickerTile(
          value: _customer != null ? '${_customer!['name']} - ${_customer!['debtor_no']}' : null,
          hint: 'Select customer',
          loading: false,
          enabled: true,
          onTap: () => _pickCustomer(customers),
        ),
        const SizedBox(height: 12),

        // ── Invoice ───────────────────────────────────────────────────────
        _sectionLabel('Invoice'),
        _pickerTile(
          value: _invoice != null ? '#${_invoice!['id']} (${_invoice!['inv_no'] ?? ''})' : null,
          hint: _customer == null ? 'Select customer first' : (_loadingInvoices ? 'Loading…' : 'Select invoice'),
          loading: _loadingInvoices,
          enabled: _customer != null && !_loadingInvoices && _invoices.isNotEmpty,
          onTap: _pickInvoice,
        ),
        if (_customer != null && !_loadingInvoices && _invoices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('No placed invoices for this customer',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.error)),
          ),
        const SizedBox(height: 12),

        // ── Item ──────────────────────────────────────────────────────────
        _sectionLabel('Item'),
        _pickerTile(
          value: _item?['description']?.toString(),
          hint: _invoice == null ? 'Select invoice first' : (_loadingItems ? 'Loading…' : 'Select item'),
          loading: _loadingItems,
          enabled: _invoice != null && !_loadingItems && _returnItems.isNotEmpty,
          onTap: _pickItem,
        ),
        const SizedBox(height: 12),

        // ── Return Quantity ────────────────────────────────────────────────
        if (_item != null) ...[
          Row(children: [
            Expanded(child: _sectionLabel('Return Quantity')),
            Text('Max: ${_nf.format(_maxQty)} ${_item!['unit'] ?? ''}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: WakulimaColors.primary700)),
          ]),
          _inputBox(
            child: TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(border: InputBorder.none, hintText: '0'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_enteredQty > _maxQty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Max ${_nf.format(_maxQty)}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.error)),
            ),
          const SizedBox(height: 12),

          // ── Batch Number ─────────────────────────────────────────────────
          _sectionLabel('Batch Number'),
          _inputBox(
            child: TextField(
              controller: _batchCtrl,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Optional'),
            ),
          ),
          const SizedBox(height: 16),

          // ── Item summary ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WakulimaColors.border),
            ),
            child: Column(children: [
              _summaryRow('Unit Price', _kes(_unitPrice)),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _summaryRow('Available Qty', _nf.format(_maxQty)),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _summaryRow('Return Value', _kes(_returnValue), highlight: true),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Add to cart ───────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: (_enteredQty > 0 && _enteredQty <= _maxQty) ? _addToCart : null,
                style: FilledButton.styleFrom(
                  backgroundColor: WakulimaColors.primary700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Add to Return Cart',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _cart.isNotEmpty ? WakulimaColors.primary50 : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _cart.isNotEmpty ? WakulimaColors.primary400 : WakulimaColors.border),
                  ),
                  child: Icon(Icons.shopping_cart_outlined,
                      color: _cart.isNotEmpty ? WakulimaColors.primary700 : WakulimaColors.inkMuted),
                ),
                if (_cart.isNotEmpty)
                  Positioned(
                    top: -6, right: -6,
                    child: Container(
                      width: 20, height: 20,
                      decoration: const BoxDecoration(
                          color: WakulimaColors.error, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${_cart.length}',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
          ]),
          const SizedBox(height: 20),
        ],

        // ── Cart ──────────────────────────────────────────────────────────
        if (_cart.isNotEmpty) ...[
          _sectionLabel('Return Cart'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WakulimaColors.border),
            ),
            child: Column(
              children: [
                ..._cart.asMap().entries.map((e) => _cartItemTile(e.key, e.value)),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Return Value',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
                      Text(_kes(_cartTotal),
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                              fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }

  Widget _cartItemTile(int idx, _ReturnCartItem r) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: idx < _cart.length - 1
          ? const BorderSide(color: Color(0xFFF0F0F0))
          : BorderSide.none),
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.description,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w500, color: WakulimaColors.ink)),
        Text('${_nf.format(r.qty)} ${r.unit}  ·  ${_kes(r.price)}/unit',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: WakulimaColors.inkMuted)),
        if (r.batchNo != null)
          Text('Batch: ${r.batchNo}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  color: WakulimaColors.inkMuted)),
      ])),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_kes(r.lineTotal),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
        GestureDetector(
          onTap: () => setState(() => _removeFromCart(idx)),
          child: const Icon(Icons.close, size: 16, color: WakulimaColors.error),
        ),
      ]),
    ]),
  );

  // ── History tab ────────────────────────────────────────────────────────────

  Widget _buildHistory(AsyncValue<List<Map<String, dynamic>>> returnsAsync) {
    return Column(
      children: [
        Expanded(child: returnsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(
              color: WakulimaColors.primary700, strokeWidth: 2)),
          error: (_, __) => _emptyState('Failed to load returns'),
          data: (returns) => returns.isEmpty
              ? _emptyState('No returns this month')
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: returns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ReturnTile(item: returns[i]),
                ),
        )),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
        fontWeight: FontWeight.w500, color: WakulimaColors.inkMid)),
  );

  Widget _pickerTile({
    String? value, required String hint,
    required bool loading, required bool enabled, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? WakulimaColors.primary50 : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: enabled ? WakulimaColors.primary200 : WakulimaColors.border),
        ),
        child: Row(children: [
          Expanded(child: loading
              ? Row(children: [
                  SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: WakulimaColors.primary700)),
                  const SizedBox(width: 10),
                  Text(hint, style: const TextStyle(fontFamily: 'Poppins',
                      fontSize: 13, color: WakulimaColors.inkMuted)),
                ])
              : Text(
                  value ?? hint,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: value != null ? WakulimaColors.ink : WakulimaColors.inkMuted),
                )),
          const Icon(Icons.keyboard_arrow_down, size: 20, color: WakulimaColors.inkMuted),
        ]),
      ),
    );
  }

  Widget _inputBox({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: WakulimaColors.primary50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: WakulimaColors.primary200),
    ),
    child: child,
  );

  Widget _summaryRow(String label, String value, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
            color: WakulimaColors.inkSoft)),
        Text(value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                color: highlight ? WakulimaColors.primary700 : WakulimaColors.ink)),
      ],
    ),
  );

  static Widget _emptyState(String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.keyboard_return_outlined, size: 44,
          color: WakulimaColors.inkMuted.withValues(alpha: 0.4)),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
          color: WakulimaColors.inkMuted)),
    ]),
  );
}

// ── Process Return bottom button — wrapped in the tab body ─────────────────────

// We override the tab widget for the form to include the floating bottom button.
// Done via a Stack in the Scaffold body.
// (Implemented via the build method using a persistent bottom widget outside the scroll.)

// NOTE: The process return button is in the Scaffold body fixed at the bottom.
// Re-implementing with a nested Scaffold approach per tab:

extension on _ReturnItemScreenState {
  Widget _buildReturnTab(List<Map<String, dynamic>> customers) {
    return Stack(
      children: [
        _buildReturnForm(customers),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: (_submitting || _cart.isEmpty) ? null : _processReturn,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _cart.isNotEmpty ? const Color(0xFF4A5568) : const Color(0xFFB0B0B0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            'Process Return (${_cart.length} item${_cart.length != 1 ? "s" : ""})',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Search bottom sheet ────────────────────────────────────────────────────────

class _SearchSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelFn;
  final bool Function(T, String) searchFn;

  const _SearchSheet({
    required this.title, required this.items,
    required this.labelFn, required this.searchFn,
  });

  @override
  State<_SearchSheet<T>> createState() => _SearchSheetState<T>();
}

class _SearchSheetState<T> extends State<_SearchSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items.where((i) => widget.searchFn(i, _query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          // Handle bar
          Container(
            width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: WakulimaColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(widget.title,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                    fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: WakulimaColors.inkMuted),
                prefixIcon: const Icon(Icons.search, size: 18, color: WakulimaColors.inkMuted),
                filled: true, fillColor: WakulimaColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: WakulimaColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: WakulimaColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: WakulimaColors.primary700, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No matches',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        color: WakulimaColors.inkMuted)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      return ListTile(
                        title: Text(widget.labelFn(item),
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                color: WakulimaColors.ink)),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ── Return history tile ────────────────────────────────────────────────────────

class _ReturnTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ReturnTile({required this.item});

  static final _nf   = NumberFormat('#,##0.00', 'en_KE');
  static final _dfmt = DateFormat('dd MMM yyyy');

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try { return _dfmt.format(DateTime.parse(raw.toString())); }
    catch (_) { return raw.toString(); }
  }

  @override
  Widget build(BuildContext context) {
    final status       = item['status']?.toString() ?? 'draft';
    final colors       = _statusColors(status);
    final customerName = (item['customer'] as Map?)?['name']?.toString() ??
        item['debtor_no']?.toString() ?? '—';
    final dateStr      = _fmtDate(item['cn_date'] ?? item['created_at']);
    final invoice      = item['invoice'] as Map?;
    final invNo        = invoice?['inv_no']?.toString();
    final invId        = (invoice?['id'] as num?)?.toInt();

    return GestureDetector(
      onTap: invId != null
          ? () {
              // Find the nearest WidgetRef by reading api from context
              final container = ProviderScope.containerOf(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _InvoiceDetailSheet(
                    invoiceId: invId, container: container),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WakulimaColors.border)),
        child: Row(children: [
          Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: WakulimaColors.primary50,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.keyboard_return_outlined,
                  size: 20, color: WakulimaColors.primary700)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(item['cn_no']?.toString() ?? '—',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
              if (invNo != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEEF4FF),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(invNo,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w600, color: Color(0xFF1565C0))),
                ),
              ],
            ]),
            Text(customerName,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: WakulimaColors.inkMuted)),
            Text(
                'KES ${_nf.format((item['amount_total'] as num?)?.toDouble() ?? 0)}  ·  $dateStr',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration:
                  BoxDecoration(color: colors[0], borderRadius: BorderRadius.circular(20)),
              child: Text(status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: colors[1])),
            ),
            if (invId != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.chevron_right, size: 16, color: WakulimaColors.inkMuted),
              ),
          ]),
        ]),
      ),
    );
  }

  static List<Color> _statusColors(String s) {
    switch (s) {
      case 'placed':    return [const Color(0xFFEAF9EF), const Color(0xFF1A8F33)];
      case 'cancelled': return [const Color(0xFFFFEEEE), WakulimaColors.error];
      default:          return [const Color(0xFFFEF3CD), const Color(0xFF9A6B00)];
    }
  }
}

// ── Invoice detail + allocations bottom sheet ──────────────────────────────────

class _InvoiceDetailSheet extends StatefulWidget {
  final int invoiceId;
  final ProviderContainer container;
  const _InvoiceDetailSheet({required this.invoiceId, required this.container});
  @override
  State<_InvoiceDetailSheet> createState() => _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends State<_InvoiceDetailSheet> {
  static final _nf   = NumberFormat('#,##0.00', 'en_KE');
  static final _dfmt = DateFormat('dd MMM yyyy');

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try { return _dfmt.format(DateTime.parse(raw.toString())); }
    catch (_) { return raw.toString(); }
  }

  String _kes(dynamic v) => 'KES ${_nf.format((v as num?)?.toDouble() ?? 0)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = widget.container.read(apiClientProvider);
      final res = await dio
          .get('/sales/invoices/${widget.invoiceId}/allocations')
          .timeout(const Duration(seconds: 12));
      final body = res.data as Map<String, dynamic>;
      if (body['success'] == true) {
        setState(() { _data = Map<String, dynamic>.from(body['data'] as Map); _loading = false; });
      } else {
        setState(() { _error = body['message']?.toString() ?? 'Failed'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Network error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(children: [
        // Handle
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: WakulimaColors.border, borderRadius: BorderRadius.circular(2)),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 18, color: WakulimaColors.primary700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _data != null
                    ? 'Invoice ${(_data!['invoice'] as Map?)?['inv_no'] ?? '#${widget.invoiceId}'}'
                    : 'Invoice Details',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                    fontWeight: FontWeight.w700, color: WakulimaColors.ink),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: WakulimaColors.inkMuted),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        const Divider(height: 1),
        // Body
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: WakulimaColors.primary700, strokeWidth: 2))
            : _error != null
                ? Center(child: Text(_error!,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        color: WakulimaColors.error)))
                : _buildContent(ctrl)),
      ]),
    );
  }

  Widget _buildContent(ScrollController ctrl) {
    final inv          = _data!['invoice'] as Map;
    final allocations  = (_data!['allocations'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ?? [];
    final totalAlloc   = (_data!['total_allocated'] as num?)?.toDouble() ?? 0;
    final outstanding  = (_data!['outstanding_balance'] as num?)?.toDouble() ?? 0;
    final amountTotal  = (inv['amount_total'] as num?)?.toDouble() ?? 0;

    return ListView(controller: ctrl, padding: const EdgeInsets.all(16), children: [

      // ── Invoice summary card ─────────────────────────────────────────────
      _card(children: [
        _row('Invoice No', inv['inv_no']?.toString() ?? '—'),
        _divider(),
        _row('Invoice Total', _kes(amountTotal), highlight: true),
        _divider(),
        _row('Total Allocated', _kes(totalAlloc)),
        _divider(),
        _row('Outstanding Balance', _kes(outstanding),
            highlight: true,
            valueColor: outstanding > 0 ? WakulimaColors.error : WakulimaColors.success),
      ]),
      const SizedBox(height: 16),

      // ── Allocations ──────────────────────────────────────────────────────
      const Text('Allocations',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
      const SizedBox(height: 8),

      if (allocations.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WakulimaColors.border)),
          child: const Center(
            child: Text('No allocations yet',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: WakulimaColors.inkMuted)),
          ),
        )
      else
        _card(children: [
          ...allocations.asMap().entries.map((e) {
            final a        = e.value;
            final isLast   = e.key == allocations.length - 1;
            final srcType  = a['source_type']?.toString() ?? '';
            final cnType   = a['cn_type']?.toString();
            final label    = _allocationLabel(srcType, cnType);
            final icon     = _allocationIcon(srcType, cnType);
            final dateStr  = _fmtDate(a['allocated_date']);
            final amount   = (a['amount'] as num?)?.toDouble() ?? 0;

            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                        color: WakulimaColors.primary50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 16, color: WakulimaColors.primary700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
                    Text(dateStr,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            color: WakulimaColors.inkMuted)),
                  ])),
                  Text(_kes(amount),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w700, color: WakulimaColors.primary700)),
                ]),
              ),
              if (!isLast) const Divider(height: 1, indent: 58, endIndent: 14),
            ]);
          }),
        ]),

      const SizedBox(height: 24),
    ]);
  }

  Widget _card({required List<Widget> children}) => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border)),
    child: Column(children: children),
  );

  Widget _row(String label, String value,
      {bool highlight = false, Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: WakulimaColors.inkSoft)),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                  color: valueColor ?? WakulimaColors.ink)),
        ]),
      );

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);

  static String _allocationLabel(String srcType, String? cnType) {
    if (srcType == 'credit_note') {
      return switch (cnType) {
        'return'         => 'Return Credit Note',
        'return_to_store'=> 'Return to Store',
        'damage'         => 'Damage Return',
        'discount'       => 'Discount Credit Note',
        'write_off'      => 'Write-Off',
        _                => 'Credit Note',
      };
    }
    if (srcType == 'payment') return 'Customer Payment';
    if (srcType == 'deposit') return 'Customer Deposit';
    return srcType.isNotEmpty ? srcType : 'Allocation';
  }

  static IconData _allocationIcon(String srcType, String? cnType) {
    if (srcType == 'credit_note') return Icons.keyboard_return_outlined;
    if (srcType == 'payment')     return Icons.payments_outlined;
    if (srcType == 'deposit')     return Icons.account_balance_outlined;
    return Icons.link;
  }
}
