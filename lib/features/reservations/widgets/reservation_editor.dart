import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../tables/controllers/table_providers.dart';
import '../../tables/models/restaurant_table.dart';
import '../controllers/reservation_providers.dart';
import '../models/reservation.dart';
import '../services/reservation_service.dart';

/// Formulario para reservar o editar. La fecha y la hora se capturan y se
/// muestran siempre en hora de Lima, sin importar la zona del dispositivo.
class ReservationEditor extends ConsumerStatefulWidget {
  const ReservationEditor({super.key, this.reservation, this.initialTableId});
  final Reservation? reservation;

  /// Mesa preseleccionada al reservar desde el mosaico de una mesa.
  final String? initialTableId;
  @override
  ConsumerState<ReservationEditor> createState() => _ReservationEditorState();
}

class _ReservationEditorState extends ConsumerState<ReservationEditor> {
  final _form = GlobalKey<FormState>();
  late final _customer = TextEditingController(
    text: widget.reservation?.customer ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.reservation?.phone ?? '',
  );
  late final _party = TextEditingController(
    text: widget.reservation?.partySize.toString() ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.reservation?.notes ?? '',
  );
  late String? _tableId = widget.reservation?.tableId ?? widget.initialTableId;
  late DateTime _date = _initialWall;
  TimeOfDay? _time;
  bool _busy = false;
  String? _error;

  DateTime get _initialWall => LimaTime.wall(
    widget.reservation?.at ?? DateTime.now().add(const Duration(hours: 2)),
  );

  @override
  void initState() {
    super.initState();
    final existing = widget.reservation;
    if (existing != null) {
      final wall = LimaTime.wall(existing.at);
      _time = TimeOfDay(hour: wall.hour, minute: wall.minute);
    }
  }

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _party.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = LimaTime.wall(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: DateTime.utc(today.year, today.month, today.day),
      lastDate: DateTime.utc(today.year + 1, today.month, today.day),
      helpText: 'Fecha de la reservación (Lima)',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 13, minute: 0),
      helpText: 'Hora de la reservación (Lima)',
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_tableId == null || _time == null) {
      setState(() => _error = 'Elige la mesa y la hora.');
      return;
    }
    final session = ref.read(sessionProvider).value;
    if (session is! Authenticated) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = ReservationDraft(
      tableId: _tableId!,
      customer: _customer.text,
      phone: _phone.text,
      partySize: int.parse(_party.text),
      at: LimaTime.instant(
        _date.year,
        _date.month,
        _date.day,
        _time!.hour,
        _time!.minute,
      ),
      notes: _notes.text,
    );
    try {
      final service = ref.read(reservationServiceProvider);
      final tables = ref.read(tablesProvider).value ?? const [];
      final existing = ref.read(reservationsProvider).value ?? const [];
      final current = widget.reservation;
      if (current == null) {
        await service.create(
          draft,
          actorUid: session.user.uid,
          actorName: session.user.nombre,
          tables: tables,
          existing: existing,
        );
      } else {
        await service.edit(current, draft, tables: tables, existing: existing);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tables = [
      for (final t in ref.watch(tablesProvider).value ?? <RestaurantTable>[])
        if (t.active || t.id == widget.reservation?.tableId) t,
    ];
    final wall = _date;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          widget.reservation == null
              ? 'Nueva reservación'
              : 'Editar reservación',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: tables.any((t) => t.id == _tableId)
                        ? _tableId
                        : null,
                    decoration: const InputDecoration(labelText: 'Mesa'),
                    items: [
                      for (final t in tables)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('Mesa ${t.id} · ${t.capacity} personas'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _tableId = v),
                    validator: (v) => v == null ? 'Elige una mesa.' : null,
                  ),
                  TextFormField(
                    controller: _customer,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del cliente',
                    ),
                    validator: ReservationValidation.customer,
                  ),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                    keyboardType: TextInputType.phone,
                    validator: ReservationValidation.phone,
                  ),
                  TextFormField(
                    controller: _party,
                    decoration: const InputDecoration(
                      labelText: 'Número de personas',
                    ),
                    keyboardType: TextInputType.number,
                    validator: ReservationValidation.partySize,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event),
                          label: Text(
                            '${wall.year}-'
                            '${wall.month.toString().padLeft(2, '0')}-'
                            '${wall.day.toString().padLeft(2, '0')}',
                          ),
                          onPressed: _busy ? null : _pickDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            _time == null
                                ? 'Elegir hora'
                                : '${_time!.hour.toString().padLeft(2, '0')}:'
                                      '${_time!.minute.toString().padLeft(2, '0')}',
                          ),
                          onPressed: _busy ? null : _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Hora de Lima. Cada reservación ocupa la mesa 2 horas.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextFormField(
                    controller: _notes,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                    ),
                    validator: ReservationValidation.notes,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Pide un motivo (cancelaciones); devuelve el texto o null si se vuelve.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({super.key, required this.title, required this.action});
  final String title;
  final String action;
  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _reason,
        autofocus: true,
        maxLength: 200,
        decoration: const InputDecoration(labelText: 'Motivo'),
        validator: ReservationValidation.cancelReason,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: Text(widget.action),
      ),
    ],
  );
}
