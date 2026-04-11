import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';

class ModuleScaffold extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  const ModuleScaffold({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WakulimaColors.cream,
      appBar: AppBar(
        backgroundColor: WakulimaColors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: WakulimaColors.border,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/dashboard'),
        ),
        title: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Text(title,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 16,
              fontWeight: FontWeight.w600, color: WakulimaColors.ink,
            ),
          ),
        ]),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
