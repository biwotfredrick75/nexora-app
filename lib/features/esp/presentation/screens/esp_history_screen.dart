import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

final _espSalesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(espRepositoryProvider).getSales();
});

/// Laravel serializes Eloquent `decimal:N` casts (e.g. total_amount) as JSON
/// strings, not numbers — parse either shape defensively.
double _numVal(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// ESP module home: history of sales made to farmers/employees/transporters,
/// with the "correction interface" (edit / void / adjust a pending sale).
class EspHistoryScreen extends ConsumerWidget {
  const EspHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(_espSalesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WakulimaColors.ink),
          // Reached from the dashboard tile via context.go(), which replaces
          // the whole stack (see ModuleScaffold for the same pattern) — pop()
          // has nothing to pop back to in that case.
          onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text('Agrovets & Services',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: WakulimaColors.primary700,
        onPressed: () async {
          final created = await context.push<bool>('/esp/new');
          if (created == true) ref.invalidate(_espSalesProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('New Sale', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_espSalesProvider),
        child: salesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: WakulimaColors.primary700)),
          error: (e, __) => ListView(children: [
            const SizedBox(height: 100),
            _EmptyState(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load sales",
              subtitle: 'Check your connection and pull down to try again.',
              onRetry: () => ref.invalidate(_espSalesProvider),
            ),
          ]),
          data: (sales) => sales.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 100),
                  _EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No ESP sales yet',
                    subtitle: 'Tap "New Sale" to invoice a farmer, employee or transporter.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: sales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _SaleTile(
                    sale: sales[i],
                    onChanged: () => ref.invalidate(_espSalesProvider),
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  const _EmptyState({required this.icon, required this.title, required this.subtitle, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: WakulimaColors.primary50, shape: BoxShape.circle),
          child: Icon(icon, size: 30, color: WakulimaColors.primary700),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted)),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(foregroundColor: WakulimaColors.primary700, side: const BorderSide(color: WakulimaColors.primary700)),
          ),
        ],
      ]),
    );
  }
}

class _SaleTile extends ConsumerWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onChanged;
  const _SaleTile({required this.sale, required this.onChanged});

  bool get _partyDeducted => sale['party_deducted'] == true;
  bool get _isVoid => sale['status'] == 'void';
  bool get _canCorrect => !_partyDeducted && !_isVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = _numVal(sale['total_amount']);
    final partyType = sale['party_type']?.toString() ?? '';
    final status = sale['status']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: WakulimaColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(sale['sale_no']?.toString() ?? '',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
          ),
          _statusChip(status),
        ]),
        const SizedBox(height: 4),
        Text('${partyType[0].toUpperCase()}${partyType.substring(1)} · ${sale['sale_date']?.toString().split('T').first ?? ''}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkMuted)),
        const SizedBox(height: 8),
        Row(children: [
          Text('KES ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800, color: WakulimaColors.primary700)),
          const Spacer(),
          if (_partyDeducted)
            const Text('Deducted', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: WakulimaColors.inkMuted))
          else if (_canCorrect)
            TextButton(
              onPressed: () => _showActions(context, ref),
              child: const Text('Manage', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
      ]),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'void' => WakulimaColors.inkMuted,
      'settled' => WakulimaColors.primary700,
      'partial' => WakulimaColors.warning,
      _ => WakulimaColors.info,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: WakulimaColors.primary700),
            title: const Text('Edit items', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            onTap: () async {
              Navigator.pop(sheetContext);
              final full = await ref.read(espRepositoryProvider).getSale((sale['id'] as num).toInt());
              if (!context.mounted) return;
              final changed = await context.push<bool>('/esp/new', extra: full);
              if (changed == true) onChanged();
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune, color: WakulimaColors.warning),
            title: const Text('Adjust amount', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            onTap: () {
              Navigator.pop(sheetContext);
              _showAdjustDialog(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cancel_outlined, color: WakulimaColors.error),
            title: const Text('Void sale', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            onTap: () async {
              Navigator.pop(sheetContext);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Void this sale?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Void')),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(espRepositoryProvider).voidSale((sale['id'] as num).toInt());
                onChanged();
              }
            },
          ),
        ]),
      ),
    );
  }

  void _showAdjustDialog(BuildContext context, WidgetRef ref) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Adjust Sale'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Delta amount (+/-)'),
          ),
          TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final delta = double.tryParse(amountCtrl.text) ?? 0;
              if (delta == 0 || reasonCtrl.text.trim().isEmpty) return;
              await ref.read(espRepositoryProvider).adjustSale(
                    (sale['id'] as num).toInt(),
                    deltaAmount: delta,
                    reason: reasonCtrl.text.trim(),
                  );
              if (dCtx.mounted) Navigator.pop(dCtx);
              onChanged();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
