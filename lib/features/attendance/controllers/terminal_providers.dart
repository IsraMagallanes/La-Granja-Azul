import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_models.dart';
import '../repositories/attendance_repositories.dart';

/// Sin terminales registradas (valor por defecto); `main.dart` lo reemplaza
/// con la implementación de Firestore.
class NoTerminalRepository implements TerminalRepository {
  const NoTerminalRepository();

  @override
  Stream<AttendanceTerminal?> watchTerminal(String uid) =>
      Stream.value(null);

  @override
  Stream<List<AttendanceTerminal>> watchAll() => Stream.value(const []);

  @override
  Future<void> authorize(actor, {required String nombre, required String uid}) =>
      throw UnsupportedError('Repositorio de terminales no configurado.');

  @override
  Future<void> setActive(actor, AttendanceTerminal terminal,
          {required bool active}) =>
      throw UnsupportedError('Repositorio de terminales no configurado.');

  @override
  Future<void> resetDeviceLink(actor, AttendanceTerminal terminal) =>
      throw UnsupportedError('Repositorio de terminales no configurado.');
}

final terminalRepositoryProvider = Provider<TerminalRepository>(
  (ref) => const NoTerminalRepository(),
);
