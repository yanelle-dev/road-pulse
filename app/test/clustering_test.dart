import 'package:flutter_test/flutter_test.dart';
import 'package:road_pulse/calculations.dart';

void main() {
  group('clusterByGrid — группировка дефектов на мелком зуме', () {
    test('близкие точки сливаются, цвет берётся по худшей степени', () {
      final clusters = clusterByGrid(
        [
          (lat: 55.7510, lon: 37.6180, severity: 1),
          (lat: 55.7512, lon: 37.6182, severity: 3),
        ],
        zoom: 10,
        cellPx: 64,
      );
      expect(clusters, hasLength(1));
      expect(clusters.single.count, 2);
      expect(clusters.single.maxSeverity, 3);
      expect(clusters.single.lat, closeTo(55.7511, 1e-6));
    });

    test('далёкие точки остаются отдельными группами', () {
      final clusters = clusterByGrid(
        [
          (lat: 55.75, lon: 37.61, severity: 1),
          (lat: 59.93, lon: 30.31, severity: 2),
        ],
        zoom: 10,
        cellPx: 64,
      );
      expect(clusters, hasLength(2));
    });

    test('пустой вход — пустой результат', () {
      expect(clusterByGrid(const [], zoom: 5, cellPx: 64), isEmpty);
    });
  });
}
