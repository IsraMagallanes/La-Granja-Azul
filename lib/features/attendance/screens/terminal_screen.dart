import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../controllers/attendance_providers.dart';
import '../services/terminal_binding.dart';
import '../services/attendance_services.dart';

/// `/asistencia/terminal`: la tablet del restaurante, con una sola cámara.
/// Escanea el QR de entrada o salida, lo valida contra el servidor y muestra
/// la confirmación. Solo cuentas de terminal autorizadas llegan aquí.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  static const _resultDuration = Duration(seconds: 4);

  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _busy = false;
  ScanResult? _result;
  Timer? _clearTimer;

  @override
  void dispose() {
    _clearTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture, String terminalUid) async {
    if (_busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(terminalScanServiceProvider)
        .process(raw, terminalUid: terminalUid);
    if (!mounted) return;
    setState(() => _result = result);
    _clearTimer?.cancel();
    _clearTimer = Timer(_resultDuration, () {
      if (mounted) {
        setState(() {
          _result = null;
          _busy = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session is! TerminalAuthenticated) return const SizedBox.shrink();
    final terminal = session.terminal;
    final binding = ref.watch(terminalBindingProvider(terminal.uid));

    return Scaffold(
      appBar: AppBar(
        title: Text('Asistencia · ${terminal.nombre}'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: switch (binding) {
        AsyncData(value: DeviceBound()) => _scanner(terminal.uid),
        AsyncData(value: DeviceNotBound(:final message)) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        AsyncError() => const Center(
            child: Text('No se pudo enlazar la terminal. Revisa la conexión.'),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _scanner(String terminalUid) {
    return Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (c) => _onDetect(c, terminalUid),
            errorBuilder: (context, error) => Center(
              child: Text('No se pudo usar la cámara: ${error.errorCode.name}'),
            ),
          ),
          if (_result == null)
            const Align(
              alignment: Alignment.bottomCenter,
              child: _Hint(),
            )
          else
            _ResultPanel(result: _result!),
        ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.black54,
        padding: const EdgeInsets.all(16),
        child: const Text(
          'Muestra tu QR de entrada o salida frente a la cámara.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.success;
    final color = ok ? Colors.green.shade700 : Colors.red.shade700;
    final title = ok
        ? '${result.type!.label} registrada'
        : 'No se pudo registrar';
    final detail = ok
        ? '${result.name}\n${LimaTime.formatDateTime(result.at!)}'
        : result.message;
    return ColoredBox(
      color: color.withValues(alpha: 0.94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.check_circle : Icons.error,
                  size: 96, color: Colors.white),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
