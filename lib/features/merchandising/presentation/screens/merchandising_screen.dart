import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';
import 'package:wakulima/features/sales/data/sales_form_shared.dart';

const _green = WakulimaColors.merchandising; // 0xFF388E3C

// ─── Providers ────────────────────────────────────────────────────────────────

final _activitiesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/merchandising/activities', params: {'per_page': '100'})
        .timeout(const Duration(seconds: 12));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['data'] ?? []) as List : []);
    return list
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
});

// ─── Main Screen ──────────────────────────────────────────────────────────────

class MerchandisingScreen extends ConsumerStatefulWidget {
  const MerchandisingScreen({super.key});

  @override
  ConsumerState<MerchandisingScreen> createState() =>
      _MerchandisingScreenState();
}

class _MerchandisingScreenState extends ConsumerState<MerchandisingScreen> {
  String _search = '';
  DateTime? _filterDate;
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _timeFmt = DateFormat('HH:mm:ss');

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String get _username {
    try {
      final u = Hive.box('auth').get('user') as Map?;
      return u?['name']?.toString() ??
          u?['user_id']?.toString() ??
          'User';
    } catch (_) {
      return 'User';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(_activitiesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: WakulimaColors.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: WakulimaColors.inkMuted)),
          Text(_username,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WakulimaColors.ink)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _openForm(context, isCheckIn: true),
              icon: const Icon(Icons.login_rounded, size: 16, color: _green),
              label: const Text('Check In',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _green)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: _green.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: WakulimaColors.border),
        ),
      ),
      body: Column(children: [
        // ── Online status bar ─────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Color(0xFF43A047), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text('ONLINE',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF43A047))),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: WakulimaColors.inkMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => ref.invalidate(_activitiesProvider),
            ),
          ]),
        ),
        const Divider(height: 1),

        // ── Search + date filter ──────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WakulimaColors.border)),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: WakulimaColors.inkMuted),
                    prefixIcon: Icon(Icons.search,
                        size: 18, color: WakulimaColors.inkMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _filterDate ?? DateTime.now(),
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                        colorScheme:
                            const ColorScheme.light(primary: _green)),
                    child: child!,
                  ),
                );
                if (d != null) setState(() => _filterDate = d);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                    color: _filterDate != null
                        ? _green.withOpacity(0.1)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _filterDate != null
                            ? _green
                            : WakulimaColors.border)),
                child: Icon(Icons.calendar_today_outlined,
                    size: 18,
                    color: _filterDate != null
                        ? _green
                        : WakulimaColors.inkSoft),
              ),
            ),
            if (_filterDate != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _filterDate = null),
                child: const Icon(Icons.close,
                    size: 18, color: WakulimaColors.inkMuted),
              ),
            ],
          ]),
        ),
        const Divider(height: 1),

        // ── Activity list ─────────────────────────────────────────────────────
        Expanded(
          child: activitiesAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: _green, strokeWidth: 2)),
            error: (_, __) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 48, color: WakulimaColors.inkMuted),
                const SizedBox(height: 8),
                const Text('Failed to load activities',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: WakulimaColors.inkMuted)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(_activitiesProvider),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            data: (all) {
              var items = all.where((a) {
                if (_search.isNotEmpty) {
                  final customer = _customerName(a).toLowerCase();
                  if (!customer.contains(_search.toLowerCase())) return false;
                }
                if (_filterDate != null) {
                  final dateStr = a['created_at']?.toString() ?? '';
                  if (!dateStr
                      .startsWith(_dateFmt.format(_filterDate!))) {
                    return false;
                  }
                }
                return true;
              }).toList();

              if (items.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.assignment_outlined,
                        size: 64, color: _green.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    const Text('No activities found',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: WakulimaColors.inkMuted)),
                  ]),
                );
              }

              return RefreshIndicator(
                color: _green,
                onRefresh: () async =>
                    ref.invalidate(_activitiesProvider),
                child: Column(children: [
                  Container(
                    color: const Color(0xFFF5F5F5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(children: [
                      const Text('Activity',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: WakulimaColors.inkMuted)),
                      const Spacer(),
                      Text('${items.length} records',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: WakulimaColors.inkMuted)),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final a = items[i];
                        final type =
                            a['type']?.toString().toLowerCase() ?? '';
                        final isCheckIn = type.contains('check_in') ||
                            type.contains('checkin') ||
                            type == 'in';
                        final customer = _customerName(a);
                        final rawDate =
                            a['created_at']?.toString() ?? '';
                        String dateLabel = rawDate;
                        try {
                          final dt =
                              DateTime.parse(rawDate).toLocal();
                          dateLabel =
                              '${_dateFmt.format(dt)} ${_timeFmt.format(dt)}';
                        } catch (_) {}

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: isCheckIn
                                    ? _green.withOpacity(0.1)
                                    : WakulimaColors.error
                                        .withOpacity(0.1),
                                shape: BoxShape.circle),
                            child: Icon(
                              isCheckIn
                                  ? Icons.login_rounded
                                  : Icons.logout_rounded,
                              size: 18,
                              color: isCheckIn
                                  ? _green
                                  : WakulimaColors.error,
                            ),
                          ),
                          title: Text(
                            isCheckIn ? 'Check In' : 'Check Out',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isCheckIn
                                    ? _green
                                    : WakulimaColors.error),
                          ),
                          subtitle: Text(customer,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: WakulimaColors.ink)),
                          trailing: Text(dateLabel,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: WakulimaColors.inkMuted)),
                        );
                      },
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, isCheckIn: false),
        backgroundColor: WakulimaColors.error,
        icon: const Icon(Icons.logout_rounded, color: Colors.white),
        label: const Text('Check Out',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }

  String _customerName(Map<String, dynamic> a) {
    if (a['customer'] is Map) {
      return a['customer']['name']?.toString() ?? '—';
    }
    return a['customer_name']?.toString() ??
        a['debtor_no']?.toString() ??
        '—';
  }

  void _openForm(BuildContext context, {required bool isCheckIn}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CheckFormScreen(
        isCheckIn: isCheckIn,
        onSuccess: () => ref.invalidate(_activitiesProvider),
      ),
    ));
  }
}

// ─── Check In / Check Out Form ────────────────────────────────────────────────

class _CheckFormScreen extends ConsumerStatefulWidget {
  final bool isCheckIn;
  final VoidCallback onSuccess;
  const _CheckFormScreen(
      {required this.isCheckIn, required this.onSuccess});

  @override
  ConsumerState<_CheckFormScreen> createState() => _CheckFormScreenState();
}

class _CheckFormScreenState extends ConsumerState<_CheckFormScreen> {
  XFile? _photo;
  String? _customerId;
  String? _customerLabel;
  final _memoCtrl = TextEditingController();
  bool _submitting = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: _green),
            title: const Text('Take Photo',
                style: TextStyle(fontFamily: 'Poppins')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: _green),
            title: const Text('Choose from Gallery',
                style: TextStyle(fontFamily: 'Poppins')),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final file =
        await _picker.pickImage(source: source, maxWidth: 1024, imageQuality: 75);
    if (file != null && mounted) setState(() => _photo = file);
  }

  Future<void> _submit() async {
    if (_customerId == null) {
      _snack('Please select a customer');
      return;
    }
    setState(() => _submitting = true);

    final endpoint =
        widget.isCheckIn ? '/merchandising/check-in' : '/merchandising/check-out';
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(endpoint, data: {
        'customer_id': _customerId,
        'memo': _memoCtrl.text.trim(),
        // photo upload handled separately if needed
      }).timeout(const Duration(seconds: 15));
      final b = res.data as Map<String, dynamic>;
      if (b['success'] == true) {
        _onDone();
      } else {
        _snack(b['message']?.toString() ?? 'Failed');
      }
    } catch (e) {
      String msg = 'Error submitting.';
      if (e is DioException) {
        final code = e.response?.statusCode;
        final data = e.response?.data;
        if (data is Map && data['message'] != null) {
          msg = data['message'].toString();
        } else if (code != null) {
          msg = 'Server error ($code). Please try again.';
        } else if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          msg = 'Connection timed out. Check your network.';
        } else {
          msg = 'Network error. Check your connection.';
        }
      }
      _snack(msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onDone() {
    widget.onSuccess();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          widget.isCheckIn ? 'Checked in successfully' : 'Checked out successfully',
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: widget.isCheckIn ? _green : WakulimaColors.error,
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.of(context).pop();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: WakulimaColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(sfCustomersProvider);
    final customers = customersAsync.maybeWhen(
        data: (d) => d, orElse: () => <Map<String, dynamic>>[]);

    final isCheckIn = widget.isCheckIn;
    final title = isCheckIn ? 'Check In' : 'Check Out';
    final buttonColor = isCheckIn ? _green : WakulimaColors.error;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: WakulimaColors.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: WakulimaColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Photo ──────────────────────────────────────────────────────────
          const Text('Your Photo',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMid)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WakulimaColors.border)),
              clipBehavior: Clip.antiAlias,
              child: _photo != null
                  ? Stack(fit: StackFit.expand, children: [
                      Image.file(File(_photo!.path), fit: BoxFit.cover),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6)),
                          child: const Text('Tap to change',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: Colors.white)),
                        ),
                      ),
                    ])
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 40,
                            color: WakulimaColors.inkMuted.withOpacity(0.4)),
                        const SizedBox(height: 8),
                        const Text('Take Photo',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: WakulimaColors.inkMuted)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Customer ───────────────────────────────────────────────────────
          const Text('Customer',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMid)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              if (customers.isEmpty) {
                _snack('Loading customers, please wait…');
                return;
              }
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _CustomerPicker(
                  customers: customers,
                  onPicked: (id, label) =>
                      setState(() {
                    _customerId = id;
                    _customerLabel = label;
                  }),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                  color: _customerId == null
                      ? const Color(0xFFFCEBEB)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _customerId == null
                          ? WakulimaColors.error.withOpacity(0.3)
                          : WakulimaColors.border)),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _customerLabel ?? '',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: _customerId != null
                            ? WakulimaColors.ink
                            : WakulimaColors.inkMuted),
                  ),
                ),
                Icon(
                  customersAsync.isLoading
                      ? Icons.hourglass_empty_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: WakulimaColors.inkSoft,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Memo ───────────────────────────────────────────────────────────
          const Text('Memo',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: WakulimaColors.inkMid)),
          const SizedBox(height: 6),
          TextField(
            controller: _memoCtrl,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
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
                  borderSide:
                      BorderSide(color: buttonColor, width: 1.5)),
            ),
          ),
          const SizedBox(height: 32),

          // ── Submit button ──────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(title,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Customer Picker Sheet ────────────────────────────────────────────────────

class _CustomerPicker extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  final void Function(String id, String label) onPicked;
  const _CustomerPicker({required this.customers, required this.onPicked});

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.customers
        : widget.customers
            .where((c) =>
                (c['name'] ?? c['debtor_no'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_q.toLowerCase()) ||
                (c['debtor_no'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_q.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16))),
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
          const Text('Select Customer',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search customer…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
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
                    child: Text('No customers found',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: WakulimaColors.inkMuted)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final name = c['name']?.toString() ?? '—';
                      final code = c['debtor_no']?.toString() ?? '';
                      return ListTile(
                        dense: true,
                        title: Text(name,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        subtitle: code.isNotEmpty
                            ? Text(code,
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: WakulimaColors.inkMuted))
                            : null,
                        onTap: () {
                          widget.onPicked(
                              code.isNotEmpty ? code : name,
                              '$name - $code');
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
