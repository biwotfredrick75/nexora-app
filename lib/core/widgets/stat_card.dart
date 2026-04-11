import 'package:flutter/material.dart';
import 'package:wakulima/core/theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (unit.isNotEmpty)
            Text(unit,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: WakulimaColors.inkSoft,
              ),
            ),
          const SizedBox(height: 2),
          Text(label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: WakulimaColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
