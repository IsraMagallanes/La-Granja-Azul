import '../../roles/models/user_role.dart';
import '../models/staff_member.dart';
import '../models/staff_status.dart';

/// Búsqueda, filtros y paginación del listado de personal (lógica pura).
class StaffListQuery {
  const StaffListQuery({
    this.text = '',
    this.role,
    this.status,
    this.page = 0,
  });

  static const pageSize = 20;

  final String text;
  final UserRole? role;
  final StaffStatus? status;
  final int page;

  StaffListQuery copyWith({
    String? text,
    UserRole? Function()? role,
    StaffStatus? Function()? status,
    int? page,
  }) =>
      StaffListQuery(
        text: text ?? this.text,
        role: role == null ? this.role : role(),
        status: status == null ? this.status : status(),
        page: page ?? this.page,
      );

  List<StaffMember> filter(Iterable<StaffMember> all) {
    final needle = _fold(text.trim());
    final result = all.where((s) {
      if (role != null && s.role != role) return false;
      if (status != null && s.estado != status) return false;
      if (needle.isEmpty) return true;
      return _fold(s.nombreCompleto).contains(needle) ||
          s.documento.toLowerCase().contains(needle) ||
          s.email.toLowerCase().contains(needle);
    }).toList()
      ..sort((a, b) => _fold(a.apellidos).compareTo(_fold(b.apellidos)));
    return result;
  }

  int pageCount(int total) => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  /// Página [page] (se ajusta al rango válido) de [filtered].
  List<StaffMember> pageOf(List<StaffMember> filtered) {
    final last = pageCount(filtered.length) - 1;
    final index = page.clamp(0, last);
    final start = index * pageSize;
    final end = (start + pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  static String _fold(String input) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    var out = input.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }
}
