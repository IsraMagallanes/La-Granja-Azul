/// Hora de Perú (America/Lima). Perú no usa horario de verano: el desfase es
/// siempre UTC-5, por lo que no se necesita una base de zonas horarias.
///
/// Los instantes se guardan en Firestore como `Timestamp` (UTC). Estas
/// funciones solo convierten para mostrar y para calcular "el día" de Lima.
abstract final class LimaTime {
  static const offset = Duration(hours: -5);

  /// Reloj de pared de Lima como un `DateTime` UTC (usar solo sus campos).
  static DateTime wall(DateTime instant) => instant.toUtc().add(offset);

  /// Instante real (UTC) de una hora de pared de Lima.
  static DateTime instant(int year, int month, int day,
          [int hour = 0, int minute = 0]) =>
      DateTime.utc(year, month, day, hour, minute).subtract(offset);

  /// Inicio (00:00 Lima) del día de Lima que contiene a [at].
  static DateTime startOfDay(DateTime at) {
    final w = wall(at);
    return instant(w.year, w.month, w.day);
  }

  /// Día de Lima como `yyyy-MM-dd`.
  static String dateKey(DateTime at) {
    final w = wall(at);
    return '${w.year.toString().padLeft(4, '0')}-'
        '${w.month.toString().padLeft(2, '0')}-'
        '${w.day.toString().padLeft(2, '0')}';
  }

  /// Día de la semana ISO de Lima (1 = lunes ... 7 = domingo).
  static int weekday(DateTime at) => wall(at).weekday;

  static String formatTime(DateTime at) {
    final w = wall(at);
    return '${w.hour.toString().padLeft(2, '0')}:'
        '${w.minute.toString().padLeft(2, '0')}';
  }

  static String formatDateTime(DateTime at) =>
      '${dateKey(at)} ${formatTime(at)}';

  /// Instante de inicio del día de Lima a partir de `yyyy-MM-dd`.
  static DateTime? parseDateKey(String key) {
    final parsed = DateTime.tryParse(key);
    return parsed == null ? null : instant(parsed.year, parsed.month, parsed.day);
  }
}
