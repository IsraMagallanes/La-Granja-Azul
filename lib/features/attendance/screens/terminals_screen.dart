import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/validators/validators.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../controllers/attendance_providers.dart';
import '../models/attendance_models.dart';

enum _TerminalAction {
  resetLink,
  disable,
  enable,
  requestDeletion,
  deletionInfo,
}

/// Superadmin: autoriza, inhabilita y reactiva las terminales de asistencia del
/// restaurante, y restablece su enlace con el dispositivo. La eliminación
/// definitiva (incluida la cuenta de acceso) no se hace desde la app, que no
/// puede borrar cuentas de Authentication: aquí se **solicita** (queda
/// registrada y auditada) y la completa un script local con Admin SDK.
class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  /// Tiempo máximo de espera de una operación: sin conexión, Firestore deja
  /// la escritura pendiente y el indicador giraría indefinidamente.
  static const operationTimeout = Duration(seconds: 20);

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> {
  /// Terminales con una operación en curso: solo ellas deshabilitan sus
  /// controles; el resto de la pantalla (y de la app) sigue disponible.
  final _busy = <String>{};

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final terminals = ref.watch(terminalsProvider);
    final requested =
        ref.watch(terminalDeletionRequestsProvider).value ?? const {};

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_to_home_screen),
        label: const Text('Autorizar terminal'),
        onPressed: () => _register(session),
      ),
      body: SafeArea(
        child: terminals.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  Center(child: Text('Aún no hay terminales autorizadas.')),
                ],
              );
            }
            final sorted = [...items]
              ..sort((a, b) => a.nombre.compareTo(b.nombre));
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: sorted.length,
              itemBuilder: (_, i) =>
                  _tile(session, sorted[i], requested.contains(sorted[i].uid)),
            );
          },
        ),
      ),
    );
  }

  Widget _tile(Authenticated session, AttendanceTerminal t, bool requested) {
    final busy = _busy.contains(t.uid);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.tablet_android,
          color: t.activo ? null : scheme.outline,
        ),
        title: Text(t.nombre),
        subtitle: Text(
          t.activo
              ? 'Autorizada'
              : requested
              ? 'Inhabilitada · eliminación solicitada'
              : 'Inhabilitada',
          style: TextStyle(color: t.activo ? null : scheme.error),
        ),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PopupMenuButton<_TerminalAction>(
                tooltip: 'Opciones de ${t.nombre}',
                onSelected: (a) => _onAction(session, t, a),
                itemBuilder: (_) => [
                  if (t.activo)
                    const PopupMenuItem(
                      value: _TerminalAction.resetLink,
                      child: ListTile(
                        leading: Icon(Icons.link_off),
                        title: Text('Restablecer enlace'),
                      ),
                    ),
                  PopupMenuItem(
                    value: t.activo
                        ? _TerminalAction.disable
                        : _TerminalAction.enable,
                    child: ListTile(
                      leading: Icon(
                        t.activo ? Icons.block : Icons.check_circle_outline,
                      ),
                      title: Text(
                        t.activo
                            ? 'Inhabilitar terminal'
                            : 'Reactivar terminal',
                      ),
                    ),
                  ),
                  if (!t.activo)
                    PopupMenuItem(
                      value: requested
                          ? _TerminalAction.deletionInfo
                          : _TerminalAction.requestDeletion,
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(
                          requested
                              ? 'Ver cómo completar la eliminación'
                              : 'Solicitar eliminación definitiva',
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _onAction(
    Authenticated session,
    AttendanceTerminal t,
    _TerminalAction action,
  ) {
    final service = ref.read(terminalAdminServiceProvider);
    final actor = session.user;
    return switch (action) {
      _TerminalAction.resetLink => _confirmAndRun(
        t,
        title: 'Restablecer enlace',
        body:
            'Se desvinculará únicamente la terminal "${t.nombre}". Dejará '
            'de registrar asistencia hasta que se vuelva a enlazar iniciando '
            'sesión en la tablet. Úsalo si cambias de tablet o sospechas que '
            'las credenciales se copiaron.',
        confirm: 'Restablecer',
        success: 'Enlace de "${t.nombre}" restablecido.',
        run: () => service.resetDeviceLink(actor, t),
      ),
      _TerminalAction.disable => _confirmAndRun(
        t,
        title: 'Inhabilitar terminal',
        body:
            'La terminal "${t.nombre}" dejará de poder registrar asistencia '
            'y se invalidará su enlace con la tablet. Se conserva su '
            'historial. Podrás reactivarla, pero deberá enlazarse de nuevo.',
        confirm: 'Inhabilitar',
        success: 'Terminal "${t.nombre}" inhabilitada.',
        run: () => service.setActive(actor, t, active: false),
      ),
      _TerminalAction.enable => _confirmAndRun(
        t,
        title: 'Reactivar terminal',
        body:
            'La terminal "${t.nombre}" volverá a estar autorizada. Su '
            'enlace anterior no se recupera: la tablet debe iniciar sesión '
            'para enlazarse de nuevo.',
        confirm: 'Reactivar',
        success: 'Terminal "${t.nombre}" reactivada.',
        run: () => service.setActive(actor, t, active: true),
      ),
      _TerminalAction.requestDeletion => _confirmAndRun(
        t,
        title: 'Solicitar eliminación definitiva',
        body:
            'Se registrará (con auditoría) la solicitud de eliminar la '
            'terminal "${t.nombre}" junto con su cuenta de acceso. La app no '
            'elimina nada: el propietario completa la eliminación con un '
            'script local. Se conservan las asistencias y la auditoría. '
            'Reactivar la terminal cancela la solicitud.',
        confirm: 'Solicitar',
        success:
            'Eliminación de "${t.nombre}" solicitada. Aún no se ha '
            'eliminado: complétala con el script local.',
        run: () => service.requestDeletion(actor, t),
      ),
      _TerminalAction.deletionInfo => _showDeleteInstructions(t),
    };
  }

  /// No elimina nada: la cuenta de acceso solo se puede borrar con el script
  /// administrativo, así que la app no afirma que la terminal quedó eliminada.
  /// La terminal desaparece de la lista cuando el script termina.
  Future<void> _showDeleteInstructions(AttendanceTerminal t) {
    final dryRun = 'node delete_terminal.js ${t.uid}';
    const pending = 'node delete_terminal.js --pendientes';
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar definitivamente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La terminal "${t.nombre}" NO se elimina desde la app: la '
                'solicitud ya está registrada. Se borra, junto con su cuenta '
                'de acceso, ejecutando un script en el equipo del '
                'propietario (carpeta tools).',
              ),
              const SizedBox(height: 12),
              const Text('UID de la terminal:'),
              SelectableText(
                t.uid,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              const Text('0. Ver las solicitudes pendientes:'),
              const SelectableText(
                pending,
                style: TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Text('1. Simulación (no cambia nada):'),
              SelectableText(
                dryRun,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Text(
                '2. Eliminación real: el mismo comando con --execute.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Se conservan las asistencias y la auditoría. La '
                'terminal desaparecerá de esta lista cuando el script termine.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: t.uid));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(_snack('UID copiado.'));
              }
            },
            child: const Text('Copiar UID'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRun(
    AttendanceTerminal t, {
    required String title,
    required String body,
    required String confirm,
    required String success,
    required Future<void> Function() run,
  }) async {
    if (_busy.contains(t.uid)) return;
    final ok = await showDialog<bool>(
      context: context,
      // Se cierra con el contexto del diálogo: usar el de la pantalla cierra
      // la página del ShellRoute ("popped the last page") y deja la app
      // bloqueada tras el diálogo.
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || _busy.contains(t.uid)) return;

    setState(() => _busy.add(t.uid));
    var message = success;
    try {
      await run().timeout(TerminalsScreen.operationTimeout);
    } catch (e) {
      message = ErrorMapper.map(e).message;
    } finally {
      if (mounted) setState(() => _busy.remove(t.uid));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_snack(message));
  }

  /// Flotante y por encima del botón «Autorizar terminal»: un mensaje pegado al
  /// borde inferior lo taparía mientras dura.
  SnackBar _snack(String message) => SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
  );

  Future<void> _register(Authenticated session) async {
    final input =
        await showDialog<({String nombre, String email, String password})>(
          context: context,
          builder: (_) => const _RegisterDialog(),
        );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(terminalAdminServiceProvider)
          .register(
            session.user,
            nombre: input.nombre,
            email: input.email,
            password: input.password,
          );
      messenger.showSnackBar(
        _snack(
          'Terminal autorizada. Inicia sesión en la tablet con esa cuenta.',
        ),
      );
    } catch (e) {
      messenger.showSnackBar(_snack(ErrorMapper.map(e).message));
    }
  }
}

class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog();

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autorizar terminal'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Crea la cuenta de la tablet del restaurante. La contraseña no '
                'se guarda: anótala en un lugar seguro.',
              ),
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre (p. ej. Tablet salón)',
                ),
                validator: (v) => Validators.required(v, field: 'El nombre'),
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Correo de la terminal',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña (mín. 10)',
                ),
                validator: (v) =>
                    (v ?? '').length < 10 ? 'Mínimo 10 caracteres.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              nombre: _nombre.text.trim(),
              email: _email.text.trim(),
              password: _password.text,
            ));
          },
          child: const Text('Autorizar'),
        ),
      ],
    );
  }
}
