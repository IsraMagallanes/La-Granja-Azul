import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/permission_service.dart';
import '../services/role_navigation.dart';

final permissionServiceProvider =
    Provider<PermissionService>((ref) => const PermissionService());

final roleNavigationProvider = Provider<RoleNavigation>(
  (ref) => RoleNavigation(ref.watch(permissionServiceProvider)),
);
