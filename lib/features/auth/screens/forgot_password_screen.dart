import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/validators/validators.dart';
import '../../../core/widgets/centered_card.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);
    if (ok && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: CenteredCard(
        child: _sent
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Si el correo está registrado, recibirás un enlace para '
                    'restablecer tu contraseña.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(AppRoute.login.path),
                    child: const Text('Volver al inicio de sesión'),
                  ),
                ],
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _email,
                      enabled: !loading,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                      ),
                      validator: Validators.email,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    const AuthErrorText(),
                    AuthSubmitButton(
                      label: 'Enviar enlace',
                      loading: loading,
                      onPressed: _submit,
                    ),
                    TextButton(
                      onPressed: () => context.go(AppRoute.login.path),
                      child: const Text('Volver'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
