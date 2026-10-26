import 'package:flutter/material.dart';

import '../../features/roles/models/permission.dart';

/// Catálogo único de rutas. Las rutas de personal declaran el permiso que las
/// protege; el orden define la ruta de inicio de cada rol (la primera
/// accesible).
enum AppRoute {
  // Públicas y de autenticación.
  loading('/cargando'),
  publicMenu('/carta'),
  login('/login'),
  forgotPassword('/recuperar'),
  accessDenied('/acceso-denegado'),

  // Personal (requieren sesión y permiso).
  dashboard('/app/dashboard', 'Dashboard', Icons.dashboard, Permission.viewDashboard),
  waiter('/app/mesero', 'Mesero', Icons.room_service, Permission.takeOrders),
  kitchen('/app/cocina', 'Cocina', Icons.soup_kitchen, Permission.useKitchen),
  cashier('/app/caja', 'Caja', Icons.point_of_sale, Permission.useCashier),
  inventory('/app/inventario', 'Inventario', Icons.inventory_2, Permission.manageInventory),
  users('/app/usuarios', 'Usuarios', Icons.group, Permission.manageStaff),
  roles('/app/roles', 'Roles y permisos', Icons.admin_panel_settings, Permission.manageRoles),
  tables('/app/mesas', 'Mesas', Icons.table_restaurant, Permission.viewTables),
  menuAdmin('/app/carta', 'Carta', Icons.menu_book, Permission.manageMenu),
  orders('/app/pedidos', 'Pedidos', Icons.receipt_long, Permission.viewOrders),
  reports('/app/reportes', 'Reportes', Icons.bar_chart, Permission.viewReports);

  const AppRoute(this.path, [this.label, this.icon, this.permission]);

  final String path;
  final String? label;
  final IconData? icon;
  final Permission? permission;

  bool get isStaff => permission != null;

  static AppRoute? fromPath(String path) {
    for (final route in values) {
      if (route.path == path) return route;
    }
    return null;
  }
}
