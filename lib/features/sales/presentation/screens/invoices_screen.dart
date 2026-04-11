import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

final _invoicesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final now = DateTime.now();
  final from = '${now.year}-${now.month.toString().padLeft(2,'0')}-01';
  final to   = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
  try {
    final res  = await api.get('/sales/invoices', params: {'date_from': from, 'date_to': to, 'limit': '100'})
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

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_invoicesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
          onPressed: () => context.pop(),
        ),
        title: const Text('Invoices', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 16, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: WakulimaColors.primary600),
              onPressed: () => ref.invalidate(_invoicesProvider)),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(
            color: WakulimaColors.primary700, strokeWidth: 2)),
        error: (_, __) => _empty('Failed to load invoices'),
        data: (invoices) => invoices.isEmpty
            ? _empty('No invoices this month')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: invoices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _InvoiceTile(invoice: invoices[i]),
              ),
      ),
    );
  }

  static Widget _empty(String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.description_outlined, size: 44,
          color: WakulimaColors.inkMuted.withValues(alpha: 0.4)),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
          color: WakulimaColors.inkMuted)),
    ]),
  );
}

class _InvoiceTile extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final status  = invoice['status']?.toString() ?? 'draft';
    final colors  = _statusColors(status);
    final total   = (invoice['amount_total'] as num?)?.toDouble() ?? 0;
    final balance = (invoice['outstanding_balance'] as num?)?.toDouble() ?? total;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WakulimaColors.border)),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: WakulimaColors.primary50,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.description_outlined, size: 20,
                color: WakulimaColors.primary700)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(invoice['inv_no']?.toString() ?? '—',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
          Text('${invoice['debtor_no'] ?? ''}  ·  ${invoice['invoice_date'] ?? ''}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: WakulimaColors.inkMuted)),
          Row(children: [
            Text('KES ${_fmt(total)}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft)),
            if (balance > 0) ...[
              const Text('  ·  ', style: TextStyle(color: WakulimaColors.inkMuted)),
              Text('Bal: KES ${_fmt(balance)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: WakulimaColors.error)),
            ],
          ]),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: colors[0],
              borderRadius: BorderRadius.circular(20)),
          child: Text(status[0].toUpperCase() + status.substring(1),
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: colors[1])),
        ),
      ]),
    );
  }

  static List<Color> _statusColors(String s) {
    switch (s) {
      case 'placed':   return [const Color(0xFFEAF9EF), const Color(0xFF1A8F33)];
      case 'cancelled':return [const Color(0xFFFFEEEE), WakulimaColors.error];
      default:         return [const Color(0xFFFEF3CD), const Color(0xFF9A6B00)];
    }
  }

  static String _fmt(double v) => v.toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
