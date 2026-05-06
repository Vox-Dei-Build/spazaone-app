import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Wraps a subtree so that, in PostHog session replay, the rendered region is
/// masked at the native recorder level.
///
/// Usage:
///
/// ```dart
/// PrivateRegion(
///   child: PaystackWebView(...),
/// )
/// ```
///
/// Why this wrapper instead of using [PostHogMaskWidget] directly:
///   * One import to remember (`PrivateRegion`) for the rest of the codebase.
///   * If we ever swap PostHog for another replay tool we only edit this file
///     instead of every screen.
///   * Reads better at the call site -- `PrivateRegion` describes intent;
///     `PostHogMaskWidget` describes mechanism.
///
/// Note: PostHog 4.11's [PostHogMaskWidget] has no toggle; wrapping always
/// masks. We deliberately do not add an `enabled` parameter -- if you don't
/// want masking, don't wrap.
class PrivateRegion extends StatelessWidget {
  const PrivateRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PostHogMaskWidget(child: child);
  }
}
