import 'package:sensors_plus/sensors_plus.dart';

import '../config/constants.dart';

/// Wraps the accelerometer stream from sensors_plus. Returns raw
/// accelerometer events (includes gravity), matching what the original
/// Android app recorded via SensorManager's TYPE_ACCELEROMETER.
class AccelerometerService {
  Stream<AccelerometerEvent> start() {
    return accelerometerEventStream(
      samplingPeriod: AppConfig.accelSamplingPeriod,
    );
  }

  void stop() {
    // The subscription is cancelled by the caller; nothing else to do.
  }
}
