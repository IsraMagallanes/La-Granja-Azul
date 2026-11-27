import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/error/error_mapper.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../controllers/attendance_providers.dart';
import '../models/attendance_models.dart';
import '../services/attendance_services.dart';
import '../services/scan_validator.dart';

/// Generador del QR de asistencia (Superadmin, Admin y Cajero). Muestra un QR
/// que se renueva solo; el personal lo escanea para registrar su entrada o
/// salida. Mostrarlo no registra asistencia de nadie.
class QrGeneratorScreen extends ConsumerStatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  ConsumerState<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends ConsumerState<QrGeneratorScreen> {
  /// Se emite uno nuevo antes de que venza el anterior (45 s), para que quien
  /// escanea nunca vea un QR a punto de caducar.
  static const _renewEvery = Duration(seconds: 30);

  IssuedQr? _qr;
  Timer? _renewTimer;
  Timer? _tickTimer;
  int _remaining = 0;
  bool _busy = false;
  String? _notice;
  bool _started = false;

  @override
  void dispose() {
    _renewTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _issue() async {
    final session = ref.read(sessionProvider).value;
    if (session is! Authenticated || _busy) return;
    setState(() => _busy = true);
    try {
      final issued = await ref
          .read(qrGenerationServiceProvider)
          .issue(session.user);
      if (!mounted) return;
      setState(() {
        _qr = issued;
        _notice = null;
        _remaining = QrToken.lifetime.inSeconds;
      });
    } catch (e) {
      if (mounted) setState(() => _notice = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _start() {
    _started = true;
    _issue();
    _renewTimer = Timer.periodic(_renewEvery, (_) => _issue());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final qr = _qr;
      if (qr == null || !mounted) return;
      final left = qr.expiresAt.difference(DateTime.now()).inSeconds;
      setState(() => _remaining = left < 0 ? 0 : left);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    // Defensa de interfaz: las reglas de Firestore y el servicio también lo
    // impiden, pero esta pantalla jamás se arma para un rol no autorizado.
    if (!const QrPolicy().canGenerate(session.user.role)) {
      return const Center(
        child: Text('Tu rol no puede generar el QR de asistencia.'),
      );
    }
    if (!_started) _start();

    final qr = _qr;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'QR de asistencia',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'El personal lo escanea con su cámara. La app registra '
                  'entrada o salida según su jornada. Se renueva solo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (qr == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: qr.payload, size: 260),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Vence en $_remaining s',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_notice!),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _issue,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Renovar ahora'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
