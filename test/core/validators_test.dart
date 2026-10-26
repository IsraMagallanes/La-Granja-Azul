import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/validators/validators.dart';

void main() {
  test('email', () {
    expect(Validators.email(''), isNotNull);
    expect(Validators.email('a@b'), isNotNull);
    expect(Validators.email('a@b.pe'), isNull);
  });

  test('password', () {
    expect(Validators.password(''), isNotNull);
    expect(Validators.password('12345'), isNotNull);
    expect(Validators.password('123456'), isNull);
  });
}
