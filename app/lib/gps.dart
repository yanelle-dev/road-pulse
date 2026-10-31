import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Настройки потока позиции для детектора, карты и «Записи».
/// На Android без AndroidSettings фикс приходит раз в 5 с: «свежесть» фикса ≤ 3 с не выполняется,
/// а позиция ямы отстаёт на десятки метров.
LocationSettings gpsStreamSettings({int distanceFilter = 0}) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 1),
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    default:
      return LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
      );
  }
}