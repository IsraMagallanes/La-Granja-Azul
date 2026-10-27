import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/dashboard_screen.dart';
import '../../features/attendance/screens/attendance_admin_screen.dart';
import '../../features/attendance/screens/my_attendance_screen.dart';
import '../../features/attendance/screens/terminal_screen.dart';
import '../../features/attendance/screens/terminals_screen.dart';
import '../../features/audit/screens/audit_screen.dart';
import '../../features/auth/controllers/auth_providers.dart';
import '../../features/auth/screens/access_denied_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/cashier/screens/cashier_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/kitchen/screens/kitchen_screen.dart';
import '../../features/menu/screens/menu_admin_screen.dart';
import '../../features/menu/screens/public_menu_screen.dart';
import '../../features/orders/screens/orders_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/roles/controllers/role_providers.dart';
import '../../features/roles/screens/roles_screen.dart';
import '../../features/staff/screens/restrictions_screen.dart';
import '../../features/tables/screens/tables_screen.dart';
import '../../features/users/screens/users_screen.dart';
import '../../features/waiters/screens/waiter_screen.dart';
import '../shell/staff_shell.dart';
import '../widgets/loading_view.dart';
import 'app_routes.dart';
import 'auth_redirect.dart';

const _staffScreens = <AppRoute, Widget>{
  AppRoute.dashboard: DashboardScreen(),
  AppRoute.waiter: WaiterScreen(),
  AppRoute.kitchen: KitchenScreen(),
  AppRoute.cashier: CashierScreen(),
  AppRoute.inventory: InventoryScreen(),
  AppRoute.users: UsersScreen(),
  AppRoute.roles: RolesScreen(),
  AppRoute.tables: TablesScreen(),
  AppRoute.menuAdmin: MenuAdminScreen(),
  AppRoute.orders: OrdersScreen(),
  AppRoute.reports: ReportsScreen(),
  AppRoute.attendanceAdmin: AttendanceAdminScreen(),
  AppRoute.myAttendance: MyAttendanceScreen(),
  AppRoute.terminals: TerminalsScreen(),
  AppRoute.restrictions: RestrictionsScreen(),
  AppRoute.audit: AuditScreen(),
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final redirector = AuthRedirect(ref.read(roleNavigationProvider));
  final router = GoRouter(
    initialLocation: AppRoute.loading.path,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      return redirector.redirect(state.uri.path, session.value);
    },
    routes: [
      GoRoute(
        path: AppRoute.loading.path,
        builder: (_, _) => const LoadingView(),
      ),
      GoRoute(
        path: AppRoute.publicMenu.path,
        builder: (_, _) => const PublicMenuScreen(),
      ),
      GoRoute(
        path: AppRoute.login.path,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.forgotPassword.path,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoute.attendanceTerminal.path,
        builder: (_, _) => const TerminalScreen(),
      ),
      GoRoute(
        path: AppRoute.verifyEmail.path,
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoute.accessDenied.path,
        builder: (_, _) => const AccessDeniedScreen(),
      ),
      ShellRoute(
        builder: (_, _, child) => StaffShell(child: child),
        routes: [
          for (final entry in _staffScreens.entries)
            GoRoute(
              path: entry.key.path,
              pageBuilder: (_, _) => NoTransitionPage(child: entry.value),
            ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
