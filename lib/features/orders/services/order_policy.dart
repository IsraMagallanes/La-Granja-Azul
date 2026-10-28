import '../../users/models/app_user.dart';
import '../../roles/models/user_role.dart';
import '../models/restaurant_order.dart';

abstract final class OrderPolicy {
  static bool admin(AppUser user) =>
      user.activo &&
      (user.role == UserRole.admin || user.role == UserRole.superadmin);
  static bool canOpen(AppUser user) =>
      user.activo && (admin(user) || user.role == UserRole.mesero);
  static bool canEdit(AppUser user, RestaurantOrder order) =>
      order.editable &&
      canOpen(user) &&
      (admin(user) || order.waiterId == user.uid);
}
