import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/controllers/auth_providers.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/roles/controllers/role_providers.dart';
import '../../features/users/models/app_user.dart';
import '../config/app_config.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_mark.dart';
import '../widgets/breakpoints.dart';

/// Marco responsivo del personal, según la referencia visual: panel lateral
/// azul marino con el logotipo (extendido en escritorio, de iconos en tablet),
/// barra superior blanca con el usuario, y en celular encabezado azul marino
/// con cajón de navegación. Solo lista las rutas permitidas al rol.
class StaffShell extends ConsumerWidget {
  const StaffShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();

    final user = session.user;
    final routes = ref
        .watch(roleNavigationProvider)
        .routesFor(user.role, onShift: session.onShift);
    final location = GoRouterState.of(context).uri.path;
    final index = routes.indexWhere((r) => r.path == location);
    final title = index < 0 ? AppConfig.appName : routes[index].label!;
    final sidebar = Breakpoints.usesRail(context);
    final expanded = Breakpoints.isWide(context);

    void go(AppRoute r) => context.go(r.path);
    void signOut() => ref.read(authControllerProvider.notifier).signOut();

    if (!sidebar) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          flexibleSpace: const BrandBackdrop(showPlate: false),
          title: const BrandWordmark(size: 15),
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout),
              onPressed: signOut,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        drawer: Drawer(
          backgroundColor: AppColors.navy,
          child: SafeArea(
            child: _Sidebar(
              routes: routes,
              selected: index < 0 ? null : index,
              expanded: true,
              user: user,
              onSelect: (r) {
                Navigator.of(context).pop();
                go(r);
              },
            ),
          ),
        ),
        body: child,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            routes: routes,
            selected: index < 0 ? null : index,
            expanded: expanded,
            user: user,
            onSelect: go,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: title,
                  user: user,
                  showName: expanded,
                  onSignOut: signOut,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.routes,
    required this.selected,
    required this.expanded,
    required this.user,
    required this.onSelect,
  });

  final List<AppRoute> routes;
  final int? selected;
  final bool expanded;
  final AppUser user;
  final ValueChanged<AppRoute> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(expanded ? 'sidebar-expanded' : 'sidebar-compact'),
    width: expanded ? 248 : 76,
    color: AppColors.navy,
    child: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(expanded ? 20 : 0, 20, 12, 16),
            child: Align(
              alignment: expanded ? Alignment.centerLeft : Alignment.center,
              child: expanded
                  ? const BrandWordmark(size: 24)
                  : const BrandWordmark(size: 11),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: routes.length,
            itemBuilder: (context, i) => _SidebarItem(
              route: routes[i],
              selected: i == selected,
              expanded: expanded,
              onTap: () => onSelect(routes[i]),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _Avatar(user.nombre),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        user.role.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.route,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final AppRoute route;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.white : Colors.white70;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: expanded ? '' : route.label!,
        child: Material(
          color: selected ? AppColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 14 : 0,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(route.icon, color: color, size: 22),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        route.label!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.user,
    required this.showName,
    required this.onSignOut,
  });

  final String title;
  final AppUser user;
  final bool showName;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    elevation: 0,
    shape: const Border(bottom: BorderSide(color: AppColors.line)),
    child: SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Avatar(user.nombre),
            if (showName) ...[
              const SizedBox(width: 10),
              Text(
                user.role.label,
                style: const TextStyle(color: AppColors.inkMuted),
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout, color: AppColors.inkMuted),
              onPressed: onSignOut,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 17,
    backgroundColor: AppColors.blue,
    child: Text(
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
      style: const TextStyle(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
