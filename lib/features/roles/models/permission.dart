/// Acciones sobre un módulo. `special` agrupa lo que no es CRUD (asignar
/// administradores, solicitar la eliminación definitiva de una terminal...).
enum PermissionAction {
  read('Ver'),
  create('Crear'),
  update('Editar'),
  delete('Eliminar'),
  special('Especial');

  const PermissionAction(this.label);
  final String label;
}

/// Módulos del sistema sobre los que se conceden acciones.
enum AppModule {
  dashboard('Dashboard'),
  staff('Personal'),
  roles('Roles y permisos'),
  menu('Carta'),
  tables('Mesas'),
  orders('Pedidos'),
  reservations('Reservaciones'),
  kitchen('Cocina'),
  cashier('Caja'),
  inventory('Inventario'),
  reports('Reportes'),
  attendance('Asistencia (administración)'),
  selfAttendance('Mi asistencia'),
  terminals('Terminales'),
  restrictions('Restricciones'),
  audit('Auditoría');

  const AppModule(this.label);
  final String label;
}

/// Permiso de pantalla/módulo. Cada uno equivale a una acción concreta sobre un
/// módulo: la matriz de acciones de `PermissionService` es la única fuente de
/// verdad y estos permisos se derivan de ella.
enum Permission {
  viewDashboard(AppModule.dashboard, PermissionAction.read),
  manageAdmins(AppModule.staff, PermissionAction.special),
  manageStaff(AppModule.staff, PermissionAction.read),
  manageRoles(AppModule.roles, PermissionAction.read),
  manageMenu(AppModule.menu, PermissionAction.read),
  viewTables(AppModule.tables, PermissionAction.read),
  manageTables(AppModule.tables, PermissionAction.update),
  takeOrders(AppModule.orders, PermissionAction.create),
  viewOrders(AppModule.orders, PermissionAction.read),
  viewReservations(AppModule.reservations, PermissionAction.read),
  manageReservations(AppModule.reservations, PermissionAction.create),
  useKitchen(AppModule.kitchen, PermissionAction.read),
  useCashier(AppModule.cashier, PermissionAction.read),
  manageInventory(AppModule.inventory, PermissionAction.read),
  viewReports(AppModule.reports, PermissionAction.read),
  manageAttendance(AppModule.attendance, PermissionAction.read),
  ownAttendance(AppModule.selfAttendance, PermissionAction.read),
  manageTerminals(AppModule.terminals, PermissionAction.read),
  // Administrar restricciones (crear/levantar). Ver su estado lo puede el
  // Admin sin acceso a la pantalla (aviso informativo al contratar).
  manageRestrictions(AppModule.restrictions, PermissionAction.update),
  viewAudit(AppModule.audit, PermissionAction.read);

  const Permission(this.module, this.action);

  final AppModule module;
  final PermissionAction action;
}
