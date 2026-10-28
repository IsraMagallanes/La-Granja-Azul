import '../../../core/error/app_failure.dart';
import '../repositories/table_repository.dart';

abstract final class TableValidation {
  static String? number(String? value) =>
      RegExp(r'^[1-9][0-9]{0,3}$').hasMatch(value ?? '')
      ? null
      : 'Número entre 1 y 9999, sin ceros iniciales.';
  static String? capacity(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 50 ? 'Capacidad entre 1 y 50.' : null;
  }
}

class TableService {
  const TableService(this.repository);
  final TableRepository repository;
  Future<void> save(
    String number,
    int capacity,
    bool active, {
    required bool create,
  }) {
    final error =
        TableValidation.number(number) ?? TableValidation.capacity('$capacity');
    if (error != null) throw AppFailure(error);
    return repository.saveTable(number, capacity, active, create: create);
  }
}
