import '../models/permission.dart';
import '../models/user_role.dart';

typedef _Grants = Map<AppModule, Set<PermissionAction>>;

/// Única fuente de verdad de la matriz rol → módulo → acciones en el cliente.
/// Debe mantenerse alineada con `firestore.rules`: `tools/fixtures/
/// permission_matrix.json` se genera desde aquí y `permissions.rules.test.js`
/// lo contrasta con las reglas reales en el emulador.
///
/// Además del permiso, los roles operativos necesitan una jornada abierta
/// (entrada registrada y sin salida) para usar sus módulos operativos; el
/// Superadmin y el Admin están exentos. Ver [isShiftExempt].
class PermissionService {
  const PermissionService();

  static const _r = PermissionAction.read;
  static const _c = PermissionAction.create;
  static const _u = PermissionAction.update;
  static const _s = PermissionAction.special;

  /// Roles exentos de la condición de asistencia.
  static const _shiftExempt = {UserRole.superadmin, UserRole.admin};

  static final _Grants _adminGrants = {
    AppModule.dashboard: {_r},
    AppModule.staff: {_r, _c, _u},
    AppModule.menu: {_r, _c, _u},
    AppModule.tables: {_r, _c, _u},
    AppModule.orders: {_r, _c, _u},
    AppModule.reservations: {_r, _c, _u},
    AppModule.kitchen: {_r, _u},
    AppModule.cashier: {_r, _c, _u},
    AppModule.supplies: {_r, _c, _u, _s},
    AppModule.purchasing: {_r, _c, _u},
    AppModule.utensils: {_r, _c, _u, _s},
    AppModule.reports: {_r},
    AppModule.attendance: {_r, _u},
    AppModule.selfAttendance: {_r, _c},
    // Solo consulta: el Admin ve el estado de una restricción como aviso.
    AppModule.restrictions: {_r},
  };

  static final Map<UserRole, _Grants> _matrix = {
    UserRole.superadmin: {
      ..._adminGrants,
      AppModule.staff: {_r, _c, _u, _s},
      AppModule.roles: {_r},
      AppModule.terminals: {_r, _c, _u, _s},
      AppModule.restrictions: {_r, _c, _u},
      AppModule.audit: {_r},
    },
    UserRole.admin: _adminGrants,
    UserRole.mesero: {
      AppModule.tables: {_r},
      // Ver existencias y registrar movimientos; nunca costos (_s).
      AppModule.utensils: {_r, _c},
      AppModule.orders: {_r, _c, _u},
      AppModule.reservations: {_r, _c, _u},
      AppModule.selfAttendance: {_r, _c},
    },
    UserRole.cocina: {
      AppModule.kitchen: {_r, _u},
      // Sin costos: su acción especial (_s) es solo de la administración.
      AppModule.supplies: {_r, _c, _u},
      AppModule.orders: {_r},
      AppModule.selfAttendance: {_r, _c},
    },
    UserRole.cajero: {
      AppModule.cashier: {_r, _c, _u},
      AppModule.orders: {_r},
      AppModule.tables: {_r},
      AppModule.reservations: {_r},
      AppModule.selfAttendance: {_r, _c},
    },
  };

  /// Acciones concedidas a [role] sobre [module].
  Set<PermissionAction> actionsOf(UserRole role, AppModule module) =>
      _matrix[role]![module] ?? const {};

  bool canDo(UserRole role, AppModule module, PermissionAction action) =>
      actionsOf(role, module).contains(action);

  /// Permisos de pantalla de [role], derivados de la matriz de acciones.
  Set<Permission> permissionsOf(UserRole role) => {
    for (final p in Permission.values)
      if (canDo(role, p.module, p.action)) p,
  };

  bool can(UserRole role, Permission permission) =>
      canDo(role, permission.module, permission.action);

  /// Superadmin y Admin no necesitan registrar entrada para operar.
  bool isShiftExempt(UserRole role) => _shiftExempt.contains(role);

  /// ¿Puede [role] usar sus módulos operativos? Los exentos siempre; el resto
  /// solo con la jornada abierta (`estadoAsistencia.abierta`).
  bool hasShiftAccess(UserRole role, {required bool onShift}) =>
      isShiftExempt(role) || onShift;

  /// Matriz serializable (roles → módulo → acciones) para contrastarla con las
  /// reglas de Firestore. Solo incluye los pares con acciones concedidas.
  Map<String, Object> matrixAsJson() => {
    'shiftExemptRoles': [for (final r in _shiftExempt) r.value]..sort(),
    'modules': {
      for (final module in AppModule.values)
        module.name: {
          for (final action in PermissionAction.values)
            action.name: [
              for (final role in UserRole.values)
                if (canDo(role, module, action)) role.value,
            ],
        },
    },
  };
}
