import 'package:flutter/material.dart';

import '../../../core/time/lima_time.dart';

/// Elige fecha y hora en hora de Lima y devuelve el instante (UTC) o `null`.
Future<DateTime?> pickLimaDateTime(
  BuildContext context, {
  DateTime? initial,
  String? helpText,
}) async {
  final base = LimaTime.wall(initial ?? DateTime.now());
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(base.year, base.month, base.day),
    firstDate: DateTime(2024),
    lastDate: DateTime.now().add(const Duration(days: 1)),
    helpText: helpText,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    helpText: helpText,
  );
  if (time == null) return null;
  return LimaTime.instant(date.year, date.month, date.day, time.hour, time.minute);
}
