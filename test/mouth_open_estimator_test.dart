import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchi_toji_watch/src/mouth_open_estimator.dart';

void main() {
  const estimator = MouthOpenEstimator();

  test('returns a low score when inner lips are close', () {
    final result = estimator.estimate(
      upperInnerLip: const [math.Point(40, 50), math.Point(60, 50)],
      lowerInnerLip: const [math.Point(40, 54), math.Point(60, 54)],
      mouthOutline: const [math.Point(20, 48), math.Point(80, 56)],
    );

    expect(result, isNotNull);
    expect(result!.score, closeTo(0.067, 0.01));
  });

  test('returns a higher score when inner lips separate', () {
    final result = estimator.estimate(
      upperInnerLip: const [math.Point(40, 44), math.Point(60, 44)],
      lowerInnerLip: const [math.Point(40, 66), math.Point(60, 66)],
      mouthOutline: const [math.Point(20, 42), math.Point(80, 68)],
    );

    expect(result, isNotNull);
    expect(result!.score, closeTo(0.367, 0.01));
  });

  test('returns null when mouth width is too small', () {
    final result = estimator.estimate(
      upperInnerLip: const [math.Point(40, 50)],
      lowerInnerLip: const [math.Point(40, 60)],
      mouthOutline: const [math.Point(40, 50), math.Point(43, 60)],
    );

    expect(result, isNull);
  });
}
