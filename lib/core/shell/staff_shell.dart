import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/controllers/auth_providers.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/roles/controllers/role_providers.dart';
import '../config/app_config.dart';
import '../widgets/breakpoints.dart';

/// Marco responsivo del personal: barra lateral en pantallas anchas y cajón
/// de navegación en pantallas estrechas. Solo lista las rutas permitidas.
class StaffShell extends ConsumerWidget {
  const StaffShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();

    final user = session.user;
    final routes = ref.watch(roleNavigationProvider).routesFor(user.role);
    final location = GoRouterState.of(context).uri.path;
    final index = routes.indexWhere((r) => r.path == location);
    final selected = index < 0 ? null : index;
    final wide = Breakpoints.isWide(context);

    void go(int i) => context.go(routes[i].path);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected == null ? AppConfig.appName : routes[selected].label!,
        ),
        actions: [
          Center(child: Text(user.nombre)),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      drawer: wide
          ? null
          : NavigationDrawer(
              selectedIndex: selected,
              onDestinationSelected: (i) {
                Navigator.of(context).pop();
                go(i);
              },
              children: [
                for (final r in routes)
                  NavigationDrawerDestination(
                    icon: Icon(r.icon),
                    label: Text(r.label!),
                  ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: true,
              selectedIndex: selected,
              onDestinationSelected: go,
              destinations: [
                for (final r in routes)
                  NavigationRailDestination(
                    icon: Icon(r.icon),
                    label: Text(r.label!),
                  ),
              ],
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
