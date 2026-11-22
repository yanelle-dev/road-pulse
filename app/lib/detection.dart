import 'dart:math';

import 'constants.dart';



double bumpThresholdFor(double speedKmh) =>
    max(kBumpBaseThresholdMs2, kBumpSpeedFactor * speedKmh);



int severityFromRatio(double ratio) =>
    ratio > kSeverityHardRatio ? 3 : (ratio > kSeverityMediumRatio ? 2 : 1);

int potholeSeverity(double peakMs2, double speedKmh) =>
    severityFromRatio(peakMs2 / bumpThresholdFor(speedKmh));



class GravityFilter {
  static const double _tauSec = 0.8;
  static const double _nominalG = 9.81;
  static const double _gTolerance = 1.0;

  double _gx = 0, _gy = 0, _gz = 0;
  int? _lastUs;


  ({double vertical, double horizontal})? update(double x, double y, double z, int nowUs) {
    final last = _lastUs;
    _lastUs = nowUs;
    if (last == null) {
      _gx = x;
      _gy = y;
      _gz = z;
      return null;
    }


    if ((sqrt(x * x + y * y + z * z) - _nominalG).abs() < _gTolerance) {
      final dt = max(1, nowUs - last) / 1e6;
      final a = dt / (_tauSec + dt);
      _gx += a * (x - _gx);
      _gy += a * (y - _gy);
      _gz += a * (z - _gz);
    }

    final gn = sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (gn < 1.0) return null;

    final lx = x - _gx, ly = y - _gy, lz = z - _gz;
    final v = (lx * _gx + ly * _gy + lz * _gz) / gn;
    final hx = lx - v * _gx / gn, hy = ly - v * _gy / gn, hz = lz - v * _gz / gn;
    return (vertical: v, horizontal: sqrt(hx * hx + hy * hy + hz * hz));
  }
}