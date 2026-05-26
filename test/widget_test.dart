import 'package:flutter_test/flutter_test.dart';
import 'package:kuchi_toji_watch/main.dart';

void main() {
  testWidgets('shows a camera unavailable message when no camera exists', (
    tester,
  ) async {
    await tester.pumpWidget(const KuchiTojiWatchApp(cameras: []));
    await tester.pump();

    expect(find.text('カメラが見つかりません'), findsOneWidget);
  });
}
