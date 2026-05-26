import 'dart:math' as math;

class MouthOpenEstimate {
  const MouthOpenEstimate({
    required this.score,
    required this.verticalGap,
    required this.mouthWidth,
  });

  final double score;
  final double verticalGap;
  final double mouthWidth;
}

class MouthOpenEstimator {
  const MouthOpenEstimator();

  MouthOpenEstimate? estimate({
    required List<math.Point<int>> upperInnerLip,
    required List<math.Point<int>> lowerInnerLip,
    required List<math.Point<int>> mouthOutline,
  }) {
    if (upperInnerLip.isEmpty ||
        lowerInnerLip.isEmpty ||
        mouthOutline.length < 2) {
      return null;
    }

    final upperY = _averageY(upperInnerLip);
    final lowerY = _averageY(lowerInnerLip);
    final verticalGap = (lowerY - upperY).abs();

    final xs = mouthOutline.map((point) => point.x);
    final mouthWidth = (xs.reduce(math.max) - xs.reduce(math.min)).toDouble();
    if (mouthWidth < 8) {
      return null;
    }

    return MouthOpenEstimate(
      score: (verticalGap / mouthWidth).clamp(0, 1.2).toDouble(),
      verticalGap: verticalGap,
      mouthWidth: mouthWidth,
    );
  }

  double _averageY(List<math.Point<int>> points) {
    final total = points.fold<double>(0, (sum, point) => sum + point.y);
    return total / points.length;
  }
}
