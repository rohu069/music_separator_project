
import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/main.dart';
import 'package:retropod/screens/home_screen.dart'; // Adjust if package name is different

void main() {
  testWidgets('Music Separator App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MusicSeparatorApp());

    // Verify that our app starts.
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
