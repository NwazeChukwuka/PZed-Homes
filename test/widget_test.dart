// Location: test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/main.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/presentation/screens/dashboard_screen.dart';

void main() {
  group('P-ZED Homes App Tests', () {
    testWidgets('App loads without crashing', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (context) => AuthService()),
            ChangeNotifierProvider(create: (context) => AppState()),
          ],
          child: const PzedHomesApp(),
        ),
      );

      // Verify that the app loads
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Dashboard screen displays correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const DashboardScreen(),
        ),
      );

      // Wait for the widget to load
      await tester.pumpAndSettle();

      // Verify dashboard elements are present
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('Responsive layout adapts to screen size', (WidgetTester tester) async {
      // Test mobile layout
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: const DashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify mobile layout elements
      expect(find.byType(Scaffold), findsOneWidget);

      // Test tablet layout
      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pumpAndSettle();

      // Verify tablet layout elements
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}