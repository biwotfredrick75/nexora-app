import 'package:flutter/material.dart';
import 'package:wakulima/core/theme/app_theme.dart';

enum ModuleAccess { open, locked, comingSoon }

class AppModule {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final ModuleAccess access;
  final String route;
  final List<String> requiredRoles;

  const AppModule({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.route,
    this.access = ModuleAccess.open,
    this.requiredRoles = const [],
  });
}

class ModuleRegistry {
  static const List<AppModule> all = [
    AppModule(
      id: 'sales',
      title: 'Sales',
      description: 'Manage sales transactions and customer orders',
      icon: Icons.storefront_outlined,
      color: WakulimaColors.sales,
      route: '/sales',
      requiredRoles: ['agent', 'manager', 'admin'],
    ),
    AppModule(
      id: 'inventory',
      title: 'Inventory',
      description: 'Track and manage product inventory',
      icon: Icons.inventory_2_outlined,
      color: WakulimaColors.inventory,
      route: '/inventory',
      requiredRoles: ['agent', 'manager', 'admin'],
    ),
    AppModule(
      id: 'dairy',
      title: 'Dairy',
      description: 'Manage dairy collection and processing',
      icon: Icons.local_drink_outlined,
      color: WakulimaColors.dairy,
      route: '/dairy',
      requiredRoles: ['agent', 'manager', 'admin'],
    ),
    AppModule(
      id: 'collection_lite',
      title: 'Collection Lite',
      description: 'Fast, optimised milk collection for low-end devices',
      icon: Icons.water_drop_outlined,
      color: WakulimaColors.collectionLite,
      route: '/collection',
      requiredRoles: ['agent', 'manager', 'admin'],
    ),
    AppModule(
      id: 'dispatch',
      title: 'Dispatch',
      description: 'Manage product dispatching and delivery',
      icon: Icons.local_shipping_outlined,
      color: WakulimaColors.dispatch,
      route: '/sales/dispatch',
      requiredRoles: ['dispatcher', 'manager', 'admin'],
    ),
    AppModule(
      id: 'driver',
      title: 'Driver',
      description: 'Driver management and routing',
      icon: Icons.directions_car_outlined,
      color: WakulimaColors.driver,
      route: '/driver',
      requiredRoles: ['driver', 'manager', 'admin'],
    ),
    AppModule(
      id: 'merchandising',
      title: 'Merchandising',
      description: 'Product placement and merchandising activities',
      icon: Icons.shopping_bag_outlined,
      color: WakulimaColors.merchandising,
      route: '/merchandising',
      requiredRoles: ['merchandiser', 'manager', 'admin'],
    ),
    AppModule(
      id: 'manufacturing',
      title: 'Manufacturing',
      description: 'Manage manufacturing processes and production',
      icon: Icons.precision_manufacturing_outlined,
      color: WakulimaColors.manufacturing,
      route: '/manufacturing',
      requiredRoles: ['manager', 'admin'],
    ),
    AppModule(
      id: 'purchases',
      title: 'Purchases',
      description: 'Manage purchase orders and vendor interactions',
      icon: Icons.receipt_long_outlined,
      color: WakulimaColors.purchases,
      route: '/purchases',
      requiredRoles: ['manager', 'admin'],
    ),
    AppModule(
      id: 'location',
      title: 'Location',
      description: 'Location tracking and management',
      icon: Icons.location_on_outlined,
      color: WakulimaColors.location,
      route: '/location',
      access: ModuleAccess.locked,
      requiredRoles: ['admin'],
    ),
    AppModule(
      id: 'dairy_admin',
      title: 'Dairy Admin',
      description: 'Administrative functions for dairy operations',
      icon: Icons.admin_panel_settings_outlined,
      color: WakulimaColors.dairyAdmin,
      route: '/dairy-admin',
      requiredRoles: ['admin'],
    ),
    AppModule(
      id: 'sales_management',
      title: 'Sales Management',
      description: 'Sales data analysis and reporting',
      icon: Icons.assessment_outlined,
      color: WakulimaColors.salesMgmt,
      route: '/sales-management',
      access: ModuleAccess.locked,
      requiredRoles: ['admin'],
    ),
    AppModule(
      id: 'analytics',
      title: 'Analytics',
      description: 'Business analytics and performance metrics',
      icon: Icons.bar_chart_outlined,
      color: WakulimaColors.analytics,
      route: '/analytics',
      requiredRoles: ['manager', 'admin'],
    ),
    AppModule(
      id: 'quality',
      title: 'Quality Control',
      description: 'Product quality assurance and control',
      icon: Icons.fact_check_outlined,
      color: WakulimaColors.quality,
      route: '/quality',
      requiredRoles: ['manager', 'admin'],
    ),
  ];

  static AppModule? findById(String id) =>
      all.where((m) => m.id == id).firstOrNull;

  static List<AppModule> forRole(String role) =>
      all.where((m) => m.requiredRoles.contains(role)).toList();
}
