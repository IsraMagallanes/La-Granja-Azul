import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/attendance_repositories.dart';

/// Almacén local del secreto que enlaza una cuenta de terminal con la tablet
/// física. Vive solo en ese dispositivo: unas credenciales copiadas no lo
/// incluyen.
abstract interface class DeviceKeyStore {
  Future<String?> read(String terminalUid);
  Future<void> write(String terminalUid, String key);
  Future<void> clear(String terminalUid);
}

class SharedPrefsDeviceKeyStore implements DeviceKeyStore {
  static String _name(String uid) => 'terminal_key_$uid';

  @override
  Future<String?> read(String terminalUid) async =>
      (await SharedPreferences.getInstance()).getString(_name(terminalUid));

  @override
  Future<void> write(String terminalUid, String key) async {
    await (await SharedPreferences.getInstance()).setString(_name(terminalUid), key);
  }

  @override
  Future<void> clear(String terminalUid) async {
    await (await SharedPreferences.getInstance()).remove(_name(terminalUid));
  }
}

sealed class BindingStatus {
  const BindingStatus();
}

class DeviceBound extends BindingStatus {
  const DeviceBound();
}

class DeviceNotBound extends BindingStatus {
  const DeviceNotBound(this.message);

  final String message;
}

/// Enlaza la terminal con este dispositivo la primera vez que inicia sesión.
/// El secreto se registra una sola vez en el servidor (`terminalClaves`, no
/// legible desde ningún cliente); cada marcación lo demuestra con
/// `terminalPruebas`. Si la clave ya existe en el servidor pero este equipo no
/// la tiene, el Superadmin debe restablecer el enlace.
class TerminalBindingService {
  const TerminalBindingService(this._store, this._repo, {this._random});

  final DeviceKeyStore _store;
  final TerminalScanRepository _repo;
  final Random? _random;

  static String generateKey([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<BindingStatus> ensureBound(String terminalUid) async {
    if (await _store.read(terminalUid) != null) return const DeviceBound();
    final key = generateKey(_random);
    // Se guarda primero: si la respuesta del servidor se pierde, no se
    // intentará registrar otro secreto distinto.
    await _store.write(terminalUid, key);
    try {
      await _repo.enroll(terminalUid: terminalUid, key: key);
      return const DeviceBound();
    } catch (_) {
      await _store.clear(terminalUid);
      return const DeviceNotBound(
        'Esta cuenta de terminal ya está enlazada a otro dispositivo (o no se '
        'pudo conectar). Pide al Superadmin que restablezca el enlace y vuelve '
        'a iniciar sesión en esta tablet.',
      );
    }
  }
}
