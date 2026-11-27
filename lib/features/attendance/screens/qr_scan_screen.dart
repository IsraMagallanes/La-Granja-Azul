import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../controllers/attendance_providers.dart';
import '../services/attendance_services.dart';
import '../services/scan_validator.dart';

/// Escáner de asistencia (Mesero, Cocina y Cajero): abre la cámara, lee el QR
/// de un generador autorizado y registra la propia entrada o salida. No hay
/// selección manual: la jornada decide si es entrada o salida.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  static const _resultDuration = Duration(seconds: 4);

  MobileScannerController? _controller;
  bool _busy = false;
  ScanResult? _result;
  Timer? _clearTimer;

  MobileScannerController get _scanner => _controller ??=
      MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );

  @override
  void dispose() {
    _clearTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture, Authenticated session) async {
    if (_busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(attendanceScanServiceProvider)
        .process(raw, scanner: session.user);
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
    if (session is! Authenticated) return const SizedBox.shrink();
    // Defensa de interfaz: servicio y reglas de Firestore también lo impiden.
    if (!const QrPolicy().canScan(session.user.role)) {
      return const Center(
        child: Text('Tu rol no registra asistencia con QR.'),
      );
    }
    final open = ref.watch(myStateProvider(session.user.uid)).value?.abierta;
    final next = open == true ? 'salida' : 'entrada';

    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: (c) => _onDetect(c, session),
          errorBuilder: (context, error) => Center(
            child: Text('No se pudo usar la cámara: ${error.errorCode.name}'),
          ),
        ),
        if (_result == null)
          Align(
            alignment: Alignment.bottomCenter,
            child: _Hint(
              'Escanea el QR de asistencia. Se registrará tu $next '
              'automáticamente.',
            ),
          )
        else
          _ResultPanel(result: _result!),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Colors.black54,
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 18),
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
        ? LimaTime.formatDateTime(result.at!)
        : result.message;
    return ColoredBox(
      color: color.withValues(alpha: 0.94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.error,
                size: 96,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
