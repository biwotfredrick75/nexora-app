import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/app_theme.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // System UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF080d1e),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Init Hive for settings / auth tokens
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('auth');
  await Hive.openBox('customers');
  await Hive.openBox('app'); // general-purpose / offline queues
  // Init sync engine (sets up connectivity listener + periodic timer)
  await SyncEngine().init();
  runApp(
    const ProviderScope(
      child: WakulimaApp(),
    ),
  );
}
class WakulimaApp extends ConsumerWidget {
  const WakulimaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Nexora',
      debugShowCheckedModeBanner: false,
      theme: WakulimaTheme.light,
      routerConfig: appRouter,
      builder: (context, child) {
        // Prevent text scaling beyond 1.2x on large font settings (accessibility)
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1).clamp(0.8, 1.2),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
