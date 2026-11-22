import 'package:flutter_test/flutter_test.dart';
import 'package:road_pulse/calculations.dart';

void main() {
  group('activityLevel', () {
    test('пустой день — 0', () => expect(activityLevel(0, 0), 0));
    test('любой пробег — активный день', () => expect(activityLevel(30, 0), 1));
    test('одна яма без пробега — активный день', () => expect(activityLevel(0, 1), 1));
    test('5 км — средний уровень', () => expect(activityLevel(5000, 0), 2));
    test('3 дефекта — средний уровень', () => expect(activityLevel(100, 3), 2));
    test('20 км или 8 дефектов — максимум', () {
      expect(activityLevel(20000, 0), 3);
      expect(activityLevel(0, 8), 3);
    });
  });
}
