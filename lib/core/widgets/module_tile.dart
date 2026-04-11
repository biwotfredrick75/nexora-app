import 'package:flutter/material.dart';
import 'package:wakulima/core/router/module_registry.dart';
import 'package:wakulima/core/theme/app_theme.dart';

class ModuleTile extends StatefulWidget {
  final AppModule module;
  final VoidCallback onTap;

  const ModuleTile({super.key, required this.module, required this.onTap});

  @override
  State<ModuleTile> createState() => _ModuleTileState();
}

class _ModuleTileState extends State<ModuleTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 120),
        lowerBound: 0.0,
        upperBound: 0.03);
    _scale = Tween(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isLocked => widget.module.access == ModuleAccess.locked;

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final color = _isLocked ? WakulimaColors.inkMuted : m.color;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: WakulimaColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: WakulimaColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: WakulimaColors.primary900.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: icon + lock badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _isLocked
                          ? WakulimaColors.surface
                          : color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(m.icon,
                        color: _isLocked ? WakulimaColors.inkMuted : color,
                        size: 18),
                  ),
                  const Spacer(),
                  if (_isLocked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: WakulimaColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: WakulimaColors.border, width: 1),
                      ),
                      child: const Icon(Icons.lock_outline,
                          size: 13, color: WakulimaColors.inkMuted),
                    )
                  else
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),

              const Spacer(),

              // Title
              Text(
                m.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _isLocked ? WakulimaColors.inkMuted : WakulimaColors.ink,
                ),
              ),
              const SizedBox(height: 3),

              // Description
              Text(
                m.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: WakulimaColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
