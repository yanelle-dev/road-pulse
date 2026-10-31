import 'package:flutter_test/flutter_test.dart';
import 'package:road_pulse/calculations.dart';
import 'package:road_pulse/detection.dart';

void main() {
  group('bumpThresholdFor — порог растёт со скоростью', () {
    test('на малой скорости действует базовый порог', () {
      expect(bumpThresholdFor(20), 7.0);
      expect(bumpThresholdFor(50), 7.0);
    });

    test('на высокой скорости порог пропорционален скорости', () {
      expect(bumpThresholdFor(100), closeTo(12.0, 1e-9));
      expect(bumpThresholdFor(150), closeTo(18.0, 1e-9));
    });
  });

  group('серьёзность — по превышению порога, а не по нормализованной силе', () {
    test('границы по отношению к порогу', () {
      expect(severityFromRatio(1.9), 1);
      expect(severityFromRatio(2.1), 2);
      expect(severityFromRatio(3.6), 3);
    });

    test('одна и та же сила на разных скоростях даёт разную серьёзность', () {
      expect(potholeSeverity(10, 40), 1);
      expect(potholeSeverity(15, 40), 2);
      expect(potholeSeverity(25, 40), 3);
      expect(potholeSeverity(30, 100), 2);
      expect(potholeSeverity(45, 100), 3);
    });
  });

  group('defectSeverity — ответ сервера и фолбэк для старых ответов', () {
    test('берёт severity сервера и ограничивает диапазон 1..3', () {
      expect(defectSeverity({'severity': 3}), 3);
      expect(defectSeverity({'severity': 7}), 3);
      expect(defectSeverity({'severity': 0}), 1);
    });

    test('без severity считает по нормализованной силе', () {
      expect(defectSeverity({'max_force': 10.0}), 1);
      expect(defectSeverity({'max_force': 25.0}), 2);
      expect(defectSeverity({'max_force': 31}), 3);
      expect(defectSeverity({}), 1);
    });
  });

  group('GravityFilter — вертикаль относительно гравитации', () {
    test('на первом сэмпле ответа нет', () {
      expect(GravityFilter().update(0, 0, 9.81, 0), isNull);
    });

    test('вертикаль не зависит от ориентации телефона', () {
      for (final g in [(0.0, 0.0, 9.81), (9.81, 0.0, 0.0), (0.0, -9.81, 0.0)]) {
        final filter = GravityFilter();
        var t = 0;
        for (var i = 0; i < 100; i++) {
          filter.update(g.$1, g.$2, g.$3, t);
          t += 10000;
        }
        final hit = filter.update(g.$1 * 2.5, g.$2 * 2.5, g.$3 * 2.5, t)!;
        expect(hit.vertical.abs(), closeTo(14.7, 0.5));
        expect(hit.horizontal, lessThan(0.5));
      }
    });

    test('боковое ускорение попадает в горизонталь, а не в вертикаль', () {
      final filter = GravityFilter();
      var t = 0;
      for (var i = 0; i < 100; i++) {
        filter.update(0, 0, 9.81, t);
        t += 10000;
      }
      final turn = filter.update(8, 0, 9.81, t)!;
      expect(turn.horizontal, closeTo(8, 0.2));
      expect(turn.vertical.abs(), lessThan(0.2));
    });
  });
}