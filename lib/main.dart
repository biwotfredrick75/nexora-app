import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/realtime/realtime_notifier.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/app_theme.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Any uncaught error while building a widget (e.g. a bad type cast from an
  // API response) otherwise replaces the WHOLE screen with Flutter's default
  // red error screen, which has no navigation chrome at all — stranding the
  // user with no way back. Show a friendly screen with a way out instead.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: WakulimaColors.error),
              const SizedBox(height: 16),
              const Text('Something went wrong',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: WakulimaColors.ink)),
              const SizedBox(height: 8),
              const Text('This screen hit an unexpected error. Go back and try again — if it keeps happening, report it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => appRouter.go('/dashboard'),
                style: FilledButton.styleFrom(backgroundColor: WakulimaColors.primary700),
                child: const Text('Back to Dashboard', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  };
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
  // Resume real-time dashboard notifications if a session is already active
  // (e.g. app was killed and relaunched while still logged in).
  if (Hive.box('auth').get('token') != null) {
    RealtimeNotifier().connect();
  }
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
      scaffoldMessengerKey: RealtimeNotifier.messengerKey,
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
