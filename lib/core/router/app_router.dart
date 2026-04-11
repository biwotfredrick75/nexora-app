import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakulima/core/widgets/main_shell.dart';
import 'package:wakulima/features/auth/presentation/screens/login_screen.dart';
import 'package:wakulima/features/auth/presentation/screens/splash_screen.dart';
import 'package:wakulima/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:wakulima/features/collection/presentation/screens/collection_screen.dart';
import 'package:wakulima/features/dairy/presentation/screens/dairy_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/sales_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/order_entry_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/direct_sale_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/invoices_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/return_item_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/direct_delivery_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/dispatch_screen.dart';
import 'package:wakulima/features/sales/presentation/screens/loading_orders_screen.dart';
import 'package:wakulima/features/merchandising/presentation/screens/merchandising_screen.dart';
import 'package:wakulima/features/purchases/presentation/screens/purchases_screen.dart';
import 'package:wakulima/features/manufacturing/presentation/screens/manufacturing_screen.dart';
import 'package:wakulima/features/analytics/presentation/screens/analytics_screen.dart';
import 'package:wakulima/features/settings/presentation/screens/settings_screen.dart';
import 'package:wakulima/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:wakulima/features/inventory/presentation/screens/inventory_transfer_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Toggle this notifier to force the router to re-evaluate redirects.
/// Call `authNotifier.notifyListeners()` after login/logout.
final authNotifier = _AuthNotifier();

class _AuthNotifier extends ChangeNotifier {
  void onChange() => notifyListeners();
}

bool _isLoggedIn() {
  try {
    return Hive.box('auth').get('token') != null;
  } catch (_) {
    return false;
  }
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  debugLogDiagnostics: false,
  refreshListenable: authNotifier,
  redirect: (context, state) {
    final loggedIn = _isLoggedIn();
    final loc = state.matchedLocation;
    final isPublic = loc == '/login' || loc == '/splash';

    if (!loggedIn && !isPublic) return '/login';
    if (loggedIn && loc == '/login') return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),

    // Shell — wraps all main-app screens with bottom nav
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/collection',
          builder: (_, __) => const CollectionScreen(),
        ),
        GoRoute(
          path: '/dairy',
          builder: (_, __) => const DairyScreen(),
        ),
        GoRoute(
          path: '/sales',
          builder: (_, __) => const SalesScreen(),
        ),
        GoRoute(
          path: '/inventory',
          builder: (_, __) => const InventoryScreen(),
        ),
        GoRoute(
          path: '/analytics',
          builder: (_, __) => const AnalyticsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
      ],
    ),

    // Inventory sub-screens (full-screen, no bottom nav)
    GoRoute(
      path: '/inventory/transfer',
      builder: (_, __) =>
          const InventoryTransferScreen(mode: TransferMode.transferOut),
    ),
    GoRoute(
      path: '/inventory/transfer-request',
      builder: (_, __) =>
          const InventoryTransferScreen(mode: TransferMode.request),
    ),

    // Sales sub-screens (full-screen, no bottom nav)
    GoRoute(
      path: '/sales/orders',
      builder: (_, __) => const OrderEntryScreen(),
    ),
    GoRoute(
      path: '/sales/direct-sale',
      builder: (_, __) => const DirectSaleScreen(),
    ),
    GoRoute(
      path: '/sales/invoices',
      builder: (_, __) => const InvoicesScreen(),
    ),
    GoRoute(
      path: '/sales/returns',
      builder: (_, __) => const ReturnItemScreen(),
    ),
    GoRoute(
      path: '/sales/delivery',
      builder: (_, __) => const DirectDeliveryScreen(),
    ),
    GoRoute(
      path: '/sales/dispatch',
      builder: (_, __) => const DispatchScreen(),
    ),
    GoRoute(
      path: '/merchandising',
      builder: (_, __) => const MerchandisingScreen(),
    ),
    GoRoute(
      path: '/purchases',
      builder: (_, __) => const PurchasesScreen(),
    ),
    GoRoute(
      path: '/manufacturing',
      builder: (_, __) => const ManufacturingScreen(),
    ),
    GoRoute(
      path: '/sales/dispatch/orders',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return LoadingOrdersScreen(
          vehicle: extra['vehicle']?.toString() ?? '',
          date: extra['date']?.toString() ?? '',
          deliveries: (extra['deliveries'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
        );
      },
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Route not found: ${state.uri}')),
  ),
);
