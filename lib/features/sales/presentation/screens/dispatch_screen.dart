import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/utils/providers.dart';

// ─── Theme ────────────────────────────────────────────────────────────────────
const _primary = WakulimaColors.primary700;

// ─── Provider ─────────────────────────────────────────────────────────────────

final _dispatchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, date) async {
  try {
    final res = await ref
        .watch(apiClientProvider)
        .get('/sales/deliveries', params: {
      'status': 'placed',
      'date_from': date,
      'date_to': date,
      'per_page': '200',
    }).timeout(const Duration(seconds: 15));
    final b = res.data as Map<String, dynamic>;
    if (b['success'] != true) return [];
    final raw = b['data'];
    return (raw is List ? raw : (raw is Map ? raw['data'] ?? [] : []))
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});
  @override
  ConsumerState<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends ConsumerState<DispatchScreen> {
  DateTime _date = DateTime.now();
  static final _dfmt = DateFormat('yyyy-MM-dd');
  static final _dlbl = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final dateStr  = _dfmt.format(_date);
    final async    = ref.watch(_dispatchProvider(dateStr));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text('Dispatch',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_dispatchProvider(dateStr)),
          ),
        ],
      ),
      body: Column(children: [
        // ── Date picker bar ──────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 30)),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(primary: _primary)),
                  child: child!,
                ),
              );
              if (d != null) setState(() => _date = d);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: _primary),
                const SizedBox(width: 8),
                Text(_dlbl.format(_date),
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: WakulimaColors.ink)),
                const Spacer(),
                const Icon(Icons.expand_more_rounded,
                    size: 18, color: WakulimaColors.inkSoft),
              ]),
            ),
          ),
        ),
        const Divider(height: 1),
        // ── Vehicle grid ────────────────────────────────────────────────────
        Expanded(
          child: async.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: _primary, strokeWidth: 2)),
            error: (_, __) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 48, color: WakulimaColors.inkMuted),
                const SizedBox(height: 8),
                const Text('Failed to load dispatches',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: WakulimaColors.inkMuted)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(_dispatchProvider(dateStr)),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            data: (deliveries) {
              // Group by vehicle
              final Map<String, List<Map<String, dynamic>>> byVehicle = {};
              for (final d in deliveries) {
                final v = (d['vehicle']?.toString() ?? '').trim();
                if (v.isEmpty) continue;
                byVehicle.putIfAbsent(v, () => []).add(d);
              }

              if (byVehicle.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 64,
                        color: _primary.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    Text('No dispatches for ${_dlbl.format(_date)}',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: WakulimaColors.inkMuted)),
                  ]),
                );
              }

              return RefreshIndicator(
                color: _primary,
                onRefresh: () async =>
                    ref.invalidate(_dispatchProvider(dateStr)),
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: byVehicle.length,
                  itemBuilder: (_, i) {
                    final plate  = byVehicle.keys.elementAt(i);
                    final orders = byVehicle[plate]!;
                    return _VehicleCard(
                      plate: plate,
                      deliveryCount: orders.length,
                      date: dateStr,
                      deliveries: orders,
                      onTap: () => context.push(
                        '/sales/dispatch/orders',
                        extra: {
                          'vehicle': plate,
                          'date': dateStr,
                          'deliveries': orders,
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Vehicle Card ─────────────────────────────────────────────────────────────

class _VehicleCard extends StatelessWidget {
  final String plate, date;
  final int deliveryCount;
  final List<Map<String, dynamic>> deliveries;
  final VoidCallback onTap;
  const _VehicleCard({
    required this.plate,
    required this.date,
    required this.deliveryCount,
    required this.deliveries,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WakulimaColors.border)),
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Date
            Text(date,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: WakulimaColors.inkMuted)),
            const Spacer(),
            // Truck icon
            Icon(Icons.local_shipping_outlined,
                size: 36, color: WakulimaColors.ink.withOpacity(0.75)),
            const SizedBox(height: 8),
            // Plate
            Text(plate,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: WakulimaColors.ink)),
            const SizedBox(height: 2),
            // Delivery count
            Text(
                '$deliveryCount Deliver${deliveryCount == 1 ? 'y' : 'ies'}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _primary)),
          ]),
        ),
      ),
    );
  }
}
