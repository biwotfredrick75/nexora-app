import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _scale = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    final box = Hive.box('auth');
    final token = box.get('token');
    if (token != null) {
      context.go('/dashboard');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WakulimaColors.primary800,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Opacity(
            opacity: _fade.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      color: WakulimaColors.primary700,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(
                        color: WakulimaColors.primary900.withOpacity(0.4),
                        blurRadius: 24, offset: const Offset(0, 8),
                      )],
                    ),
                    child: const Icon(Icons.water_drop, color: Colors.white, size: 46),
                  ),
                  const SizedBox(height: 24),
                  const Text('WAKULIMA',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 28, fontWeight: FontWeight.w700,
                      color: Colors.white, letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Dairy Management Platform',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13, fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.65),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 60),
                  SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
