import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ondevice_slm_app/main.dart';
import 'package:ondevice_slm_app/services/inference_service.dart';
import 'package:ondevice_slm_app/screens/chat_screen.dart';

void main() {
  testWidgets('home screen shows counter and increments', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Should show counter starting at 0
    expect(find.text('0'), findsOneWidget);

    // Tap the increment button and check value
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('chat screen sends a message and receives reply', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(inferenceService: MockInferenceService())));

    await tester.enterText(find.byType(TextField), 'Hello test');
    await tester.tap(find.text('Send'));
    await tester.pump();

    // allow async reply to come back
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Gemma reply'), findsOneWidget);
  });
}
