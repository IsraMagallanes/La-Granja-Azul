import 'package:equatable/equatable.dart';

import '../../../core/time/lima_time.dart';

/// Horario o turno (`horarios/{id}`). Si la hora de fin es menor o igual a la
/// de inicio, el turno es nocturno y termina al día siguiente.
class Schedule extends Equatable {
  const Schedule({
    required this.id,
    required this.nombre,
    required this.inicioMin,
    required this.finMin,
    required this.toleranciaMin,
    required this.dias,
    this.activo = true,
  });

  final String id;
  final String nombre;

  /// Minutos desde medianoche (0..1439).
  final int inicioMin;
  final int finMin;
  final int toleranciaMin;

  /// Días de la semana ISO (1 = lunes ... 7 = domingo).
  final List<int> dias;
  final bool activo;

  static final _time = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');

  bool get esNocturno => finMin <= inicioMin;

  Duration get duracion =>
      Duration(minutes: esNocturno ? 1440 - inicioMin + finMin : finMin - inicioMin);

  String get horaInicio => formatMinutes(inicioMin);
  String get horaFin => formatMinutes(finMin);

  static String formatMinutes(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  /// Convierte `HH:mm` a minutos; `null` si el formato es inválido.
  static int? parseMinutes(String? value) {
    if (value == null || !_time.hasMatch(value)) return null;
    return int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3));
  }

  /// Instante de inicio del turno que arranca el día de Lima [dayStart].
  DateTime startOn(DateTime dayStart) {
    final w = LimaTime.wall(dayStart);
    return LimaTime.instant(w.year, w.month, w.day, inicioMin ~/ 60, inicioMin % 60);
  }

  DateTime endOn(DateTime dayStart) => startOn(dayStart).add(duracion);

  /// El turno aplica si arranca en un día de la semana configurado.
  bool appliesOn(DateTime dayStart) => dias.contains(LimaTime.weekday(dayStart));

  /// Minutos de tardanza de [entrada] (0 si llegó dentro de la tolerancia).
  /// Toma como referencia el inicio de turno más cercano (ayer, hoy o mañana),
  /// lo que resuelve los turnos nocturnos que cruzan la medianoche.
  int lateMinutes(DateTime entrada) {
    final today = LimaTime.startOfDay(entrada);
    DateTime? best;
    for (final shift in [-1, 0, 1]) {
      final start = startOn(today.add(Duration(days: shift)));
      if (best == null ||
          start.difference(entrada).abs() < best.difference(entrada).abs()) {
        best = start;
      }
    }
    final limit = best!.add(Duration(minutes: toleranciaMin));
    final late = entrada.difference(limit).inMinutes;
    return late > 0 ? late : 0;
  }

  static Schedule? fromMap(String id, Map<String, dynamic> data) {
    final start = parseMinutes(data['horaInicio'] as String?);
    final end = parseMinutes(data['horaFin'] as String?);
    if (start == null || end == null) return null;
    return Schedule(
      id: id,
      nombre: (data['nombre'] as String?) ?? '',
      inicioMin: start,
      finMin: end,
      toleranciaMin: (data['toleranciaMin'] as num?)?.toInt() ?? 0,
      dias: [for (final d in (data['dias'] as List?) ?? const []) (d as num).toInt()],
      activo: data['activo'] != false,
    );
  }

  Map<String, Object?> toMap() => {
        'nombre': nombre,
        'horaInicio': horaInicio,
        'horaFin': horaFin,
        'toleranciaMin': toleranciaMin,
        'dias': dias,
        'activo': activo,
      };

  /// Validación de los datos del formulario; devuelve el primer error.
  static String? validate({
    required String nombre,
    required String? horaInicio,
    required String? horaFin,
    required int toleranciaMin,
    required List<int> dias,
  }) {
    if (nombre.trim().length < 2 || nombre.trim().length > 40) {
      return 'El nombre debe tener entre 2 y 40 caracteres.';
    }
    final start = parseMinutes(horaInicio);
    final end = parseMinutes(horaFin);
    if (start == null || end == null) return 'Las horas deben tener formato HH:mm.';
    if (start == end) return 'La hora de inicio y fin no pueden ser iguales.';
    if (toleranciaMin < 0 || toleranciaMin > 120) {
      return 'La tolerancia debe estar entre 0 y 120 minutos.';
    }
    if (dias.isEmpty) return 'Selecciona al menos un día.';
    return null;
  }

  @override
  List<Object?> get props =>
      [id, nombre, inicioMin, finMin, toleranciaMin, dias, activo];
}
