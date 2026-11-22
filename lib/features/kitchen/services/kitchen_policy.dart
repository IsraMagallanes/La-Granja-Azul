import '../../orders/models/restaurant_order.dart';
import '../../orders/services/order_policy.dart';
import '../../roles/models/user_role.dart';
import '../../users/models/app_user.dart';

/// Qué tan atrasado va un pedido en cocina, según los minutos desde que se
/// registró.
enum KitchenUrgency { normal, attention, late }

/// Quién mueve un pedido en cocina y cómo se ordena la cola. Las reglas de
/// Firestore repiten esta política; aquí solo decide qué botones se ofrecen.
abstract final class KitchenPolicy {
  static const attentionAfter = 15;
  static const lateAfter = 30;

  /// Cocina prepara y marca listo; Admin y Superadmin supervisan.
  static bool canOperate(AppUser user) =>
      user.activo && (user.role == UserRole.cocina || OrderPolicy.admin(user));

  /// Entrega el mesero responsable del pedido (o la administración).
  static bool canDeliver(AppUser user, RestaurantOrder order) =>
      user.activo &&
      (OrderPolicy.admin(user) ||
          (user.role == UserRole.mesero && order.waiterId == user.uid));

  static bool canAdvance(
    AppUser user,
    RestaurantOrder order,
    KitchenStatus to,
  ) =>
      order.status == OrderStatus.registrado &&
      order.kitchen?.next == to &&
      (to == KitchenStatus.entregado
          ? canDeliver(user, order)
          : canOperate(user));

  /// Pedidos de [all] que están en [status], el más antiguo primero.
  static List<RestaurantOrder> queue(
    List<RestaurantOrder> all,
    KitchenStatus status,
  ) =>
      [
        for (final o in all)
          if (o.status == OrderStatus.registrado && o.kitchen == status) o,
      ]..sort(
        (a, b) => (a.registeredAt ?? a.createdAt ?? DateTime(1970)).compareTo(
          b.registeredAt ?? b.createdAt ?? DateTime(1970),
        ),
      );

  /// Minutos desde que el pedido entró a cocina (0 si aún no hay hora).
  static int minutesWaiting(RestaurantOrder order, DateTime now) {
    final since = order.registeredAt ?? order.updatedAt;
    if (since == null) return 0;
    final minutes = now.difference(since).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  static KitchenUrgency urgency(int minutes) => minutes >= lateAfter
      ? KitchenUrgency.late
      : minutes >= attentionAfter
      ? KitchenUrgency.attention
      : KitchenUrgency.normal;
}
