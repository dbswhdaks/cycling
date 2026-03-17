import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycling/main.dart';

void main() {
  testWidgets('앱 스모크 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CyclingApp(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
