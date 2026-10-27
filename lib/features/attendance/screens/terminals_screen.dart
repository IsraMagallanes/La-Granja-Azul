import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/validators/validators.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../controllers/attendance_providers.dart';
import '../models/attendance_models.dart';

/// Superadmin: autoriza y revoca las terminales de asistencia del restaurante.
class TerminalsScreen extends ConsumerWidget {
  const TerminalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final actor = session.user;
    final terminals = ref.watch(terminalsProvider);

    Future<void> toggle(AttendanceTerminal t, bool active) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(terminalAdminServiceProvider)
            .setActive(actor, t, active: active);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
      }
    }

    Future<void> resetLink(AttendanceTerminal t) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restablecer enlace'),
          content: Text(
            'La terminal "${t.nombre}" dejará de funcionar hasta que se vuelva a '
            'enlazar iniciando sesión en la tablet. Úsalo si cambias de tablet o '
            'sospechas que las credenciales se copiaron.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restablecer')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(terminalAdminServiceProvider).resetDeviceLink(actor, t);
        messenger.showSnackBar(const SnackBar(content: Text('Enlace restablecido.')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_to_home_screen),
        label: const Text('Autorizar terminal'),
        onPressed: () => _register(context, ref),
      ),
      body: terminals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
        data: (items) => items.isEmpty
            ? const Center(child: Text('Aún no hay terminales autorizadas.'))
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final t in items)
                    SwitchListTile(
                      secondary: const Icon(Icons.tablet_android),
                      title: Text(t.nombre),
                      subtitle: Text(t.activo ? 'Autorizada' : 'Revocada'),
                      value: t.activo,
                      onChanged: (v) => toggle(t, v),
                      isThreeLine: true,
                    ),
                  // Acción por terminal: restablecer enlace con el dispositivo.
                  for (final t in items)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 72),
                        child: TextButton.icon(
                          onPressed: () => resetLink(t),
                          icon: const Icon(Icons.link_off),
                          label: Text('Restablecer enlace de ${t.nombre}'),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _register(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider).value;
    if (session is! Authenticated) return;
    final input = await showDialog<({String nombre, String email, String password})>(
      context: context,
      builder: (_) => const _RegisterDialog(),
    );
    if (input == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(terminalAdminServiceProvider).register(
            session.user,
            nombre: input.nombre,
            email: input.email,
            password: input.password,
          );
      messenger.showSnackBar(const SnackBar(
        content: Text('Terminal autorizada. Inicia sesión en la tablet con esa cuenta.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
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
                decoration: const InputDecoration(labelText: 'Nombre (p. ej. Tablet salón)'),
                validator: (v) => Validators.required(v, field: 'El nombre'),
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Correo de la terminal'),
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña (mín. 10)'),
                validator: (v) =>
                    (v ?? '').length < 10 ? 'Mínimo 10 caracteres.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
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
