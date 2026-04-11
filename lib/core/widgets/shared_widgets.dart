import 'package:flutter/material.dart';
import 'package:wakulima/core/theme/app_theme.dart';

// ─── Empty State ────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: WakulimaColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: WakulimaColors.border),
              ),
              child: Icon(icon, size: 34, color: WakulimaColors.inkMuted),
            ),
            const SizedBox(height: 20),
            Text(title,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600,
                color: WakulimaColors.inkMid),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(subtitle,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: WakulimaColors.inkMuted,
                height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Error State ─────────────────────────────────────────────────────────────

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFCEBEB),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.error_outline, size: 32, color: WakulimaColors.error),
            ),
            const SizedBox(height: 16),
            const Text('Something went wrong',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                  fontWeight: FontWeight.w600, color: WakulimaColors.inkMid)),
            const SizedBox(height: 8),
            Text(message,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: WakulimaColors.inkMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Loading Shimmer ─────────────────────────────────────────────────────────

class ShimmerList extends StatefulWidget {
  final int count;
  const ShimmerList({super.key, this.count = 6});
  @override
  State<ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<ShimmerList>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.4 + 0.3 * _anim.value;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(widget.count, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: WakulimaColors.border.withOpacity(opacity),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )),
          ),
        );
      },
    );
  }
}

// ─── Status Badge ────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  static const _colors = {
    'pending':   [Color(0xFFFEF3CD), Color(0xFF9A6B00)],
    'active':    [Color(0xFFE8F4FD), Color(0xFF1565C0)],
    'paid':      [Color(0xFFEAF9EF), Color(0xFF1A8F33)],
    'completed': [Color(0xFFEAF9EF), Color(0xFF1A8F33)],
    'confirmed': [Color(0xFFEAF9EF), Color(0xFF1A8F33)],
    'cancelled': [Color(0xFFFCEBEB), Color(0xFFA32D2D)],
    'draft':     [Color(0xFFF1EFE8), Color(0xFF5F5E5A)],
    'received':  [Color(0xFFEAF9EF), Color(0xFF1A8F33)],
    'ordered':   [Color(0xFFE8F4FD), Color(0xFF1565C0)],
  };

  @override
  Widget build(BuildContext context) {
    final key = status.toLowerCase();
    final bg = _colors[key]?[0] ?? const Color(0xFFF1EFE8);
    final fg = _colors[key]?[1] ?? WakulimaColors.inkSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status[0].toUpperCase() + status.substring(1).toLowerCase(),
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─── Info Row (label + value) ─────────────────────────────────────────────────

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(
          bottom: BorderSide(color: WakulimaColors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: WakulimaColors.inkSoft)),
          ),
          Expanded(
            child: Text(value,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w500, color: WakulimaColors.ink),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(children: [
        Text(title,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
              fontWeight: FontWeight.w700, color: WakulimaColors.inkMid,
              letterSpacing: 0.2)),
        if (action != null) ...[
          const Spacer(),
          GestureDetector(
            onTap: onAction,
            child: Text(action!,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: WakulimaColors.primary700)),
          ),
        ],
      ]),
    );
  }
}
