import 'package:equatable/equatable.dart';

/// Restricción de recontratación por documento (`restricciones/{documento}`).
/// Es informativa: nunca bloquea automáticamente una contratación.
class RehireRestriction extends Equatable {
  const RehireRestriction({
    required this.documento,
    required this.activa,
    required this.revisarEn,
    required this.establecidaPor,
  });

  final String documento;
  final bool activa;

  /// Fecha (`yyyy-MM-dd`) en que debe revisarse la restricción.
  final String revisarEn;
  final String establecidaPor;

  static RehireRestriction fromMap(String documento, Map<String, dynamic> d) =>
      RehireRestriction(
        documento: documento,
        activa: d['estado'] == 'activa',
        revisarEn: (d['revisarEn'] as String?) ?? '',
        establecidaPor: (d['establecidaPor'] as String?) ?? '',
      );

  /// `true` si ya venció la fecha de revisión.
  bool needsReview(DateTime today) {
    final due = DateTime.tryParse(revisarEn);
    return activa && due != null && !due.isAfter(today);
  }

  @override
  List<Object?> get props => [documento, activa, revisarEn, establecidaPor];
}
