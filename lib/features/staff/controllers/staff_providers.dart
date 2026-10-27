import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/models/audit_entry.dart';
import '../../audit/repositories/audit_repository.dart';
import '../models/rehire_restriction.dart';
import '../models/staff_member.dart';
import '../repositories/staff_repository.dart';
import '../services/staff_list_query.dart';
import '../services/whatsapp_invite.dart';
import '../services/staff_policy.dart';
import '../services/staff_service.dart';

/// Se sobrescriben en `main.dart` con las implementaciones de Firebase.
final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => throw UnimplementedError('staffRepositoryProvider sin override'),
);

final restrictionRepositoryProvider = Provider<RestrictionRepository>(
  (ref) =>
      throw UnimplementedError('restrictionRepositoryProvider sin override'),
);

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => throw UnimplementedError('auditRepositoryProvider sin override'),
);

final staffPolicyProvider = Provider<StaffPolicy>((ref) => const StaffPolicy());

final staffServiceProvider = Provider<StaffService>(
  (ref) => StaffService(
    ref.watch(staffRepositoryProvider),
    ref.watch(restrictionRepositoryProvider),
    policy: ref.watch(staffPolicyProvider),
  ),
);

final staffListProvider = StreamProvider<List<StaffMember>>(
  (ref) => ref.watch(staffRepositoryProvider).watchAll(),
);

final restrictionsProvider = StreamProvider<List<RehireRestriction>>(
  (ref) => ref.watch(restrictionRepositoryProvider).watchAll(),
);

final auditEntriesProvider = StreamProvider<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).watchRecent(),
);

class StaffQueryNotifier extends Notifier<StaffListQuery> {
  @override
  StaffListQuery build() => const StaffListQuery();

  void update(StaffListQuery Function(StaffListQuery) change) =>
      state = change(state);
}

final staffQueryProvider =
    NotifierProvider<StaffQueryNotifier, StaffListQuery>(StaffQueryNotifier.new);

final urlOpenerProvider = Provider<UrlOpener>((ref) => UrlLauncherOpener());

final whatsAppInviteProvider = Provider<WhatsAppInvite>(
  (ref) => WhatsAppInvite(ref.watch(urlOpenerProvider)),
);
