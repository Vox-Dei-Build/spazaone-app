import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/profile_image.dart';

/// PAS-PROFILE-IMG-403: regression coverage for the production crash where
/// stale Firebase Storage profile image URLs returned 403 and surfaced as a
/// fatal FlutterError via [CircleAvatar.backgroundImage].
///
/// These tests do not exercise the network path -- they pin the contract
/// that the widget always has an initials fallback rendered, which is the
/// safety net the hotfix relies on.
void main() {
  testWidgets('renders initials when no image is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileImageWidget(
            initials: 'Alice',
            radius: 24,
          ),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('renders initials when imageUrl is empty string', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileImageWidget(
            imageUrl: '',
            initials: 'Bob',
            radius: 24,
          ),
        ),
      ),
    );

    expect(find.text('B'), findsOneWidget);
  });

  testWidgets(
      'mounts without throwing when given a remote imageUrl '
      '(error path falls back to initials, never crashes)', (tester) async {
    // We do not allow the network in tests, but the widget tree must still
    // build without throwing. The CachedNetworkImage error pathway is what
    // would render in production when Firebase Storage replies 403.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileImageWidget(
            imageUrl: 'https://example.invalid/forbidden.jpg',
            initials: 'Carol',
            radius: 24,
          ),
        ),
      ),
    );

    // No exception should reach the test binding.
    expect(tester.takeException(), isNull);
  });
}
