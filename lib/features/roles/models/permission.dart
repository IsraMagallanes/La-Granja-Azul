/// Acciones sobre un módulo. `special` agrupa lo que no es CRUD (asignar
/// administradores....).
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
  supplies('Insumos'),
  purchasing('Compras'),
  utensils('Utensilios'),
  reports('Reportes'),
  attendance('Asistencia (administración)'),
  selfAttendance('Mi asistencia'),
  qrGenerate('Generar QR de asistencia'),
  qrScan('Escanear QR de asistencia'),
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
  manageSupplies(AppModule.supplies, PermissionAction.read),
  // Costos de insumos: solo Admin y Superadmin (Cocina nunca los lee).
  viewSupplyCosts(AppModule.supplies, PermissionAction.special),
  managePurchasing(AppModule.purchasing, PermissionAction.read),
  manageUtensils(AppModule.utensils, PermissionAction.read),
  // Costos y valoración de utensilios: solo Admin y Superadmin.
  viewUtensilCosts(AppModule.utensils, PermissionAction.special),
  viewReports(AppModule.reports, PermissionAction.read),
  manageAttendance(AppModule.attendance, PermissionAction.read),
  ownAttendance(AppModule.selfAttendance, PermissionAction.read),
  // Mostrar el QR de asistencia: solo Superadmin, Admin y Cajero.
  generateAttendanceQr(AppModule.qrGenerate, PermissionAction.create),
  // Escanear el QR con la cámara y registrar la propia entrada o salida:
  // Mesero, Cocina y Cajero.
  scanAttendanceQr(AppModule.qrScan, PermissionAction.create),
  // Administrar restricciones (crear/levantar). Ver su estado lo puede el
  // Admin sin acceso a la pantalla (aviso informativo al contratar).
  manageRestrictions(AppModule.restrictions, PermissionAction.update),
  viewAudit(AppModule.audit, PermissionAction.read);

  const Permission(this.module, this.action);

  final AppModule module;
  final PermissionAction action;
}
