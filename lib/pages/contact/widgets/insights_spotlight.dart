// One-time spotlight for the "Customer insights" AppBar icon.
//
// Why this exists:
//   The insights `IconButton` is visually similar to the kebab menu beside
//   it (same color family, same size, no label). Without a nudge, merchants
//   miss it. A one-shot spotlight on first visit — backdrop with a hole
//   over the icon plus a small "what is this?" callout — is the lightest
//   pattern that reliably bootstraps discovery without becoming a recurring
//   distraction.
//
// Persistence:
//   A single boolean flag in the local `appBox` Hive box. Mirrors the
//   pattern used by `review_prompt_service.dart` and `consent_service.dart`
//   so we don't sprinkle SharedPreferences across the codebase. The flag is
//   global (not per-customer) — once a merchant has seen the spotlight on
//   any customer profile, they don't need it again.
//
// Failure modes:
//   * Hive box not open → service silently no-ops; we treat "can't persist"
//     as "treat as already seen" so we never block the UI on local storage.
//   * Target widget unmounted / no RenderBox by the time we paint → bail,
//     same flag-write behaviour. Better to skip than to crash.
//
// API:
//   `InsightsSpotlight.maybeShow(context, key)` is fire-and-forget; the
//   caller (the AppBar) just calls it in a post-frame callback. The
//   overlay dismisses on tap-out, on a 6s safety timer, or when the user
//   actually taps the insights button (the caller can opt in to the latter
//   via `InsightsSpotlight.markSeen()`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

class InsightsSpotlight {
  static const _boxName = 'appBox';
  static const _seenKey = 'pas_seen_customer_insights_spotlight_v1';
  static const _autoDismiss = Duration(seconds: 6);
  static const _showDelay = Duration(milliseconds: 450);

  static bool _inFlight = false;

  /// Returns true if the spotlight has already been shown to this user.
  /// Treats "can't read the box" as "already seen" so we never get stuck
  /// re-showing the spotlight on every profile open if Hive failed init.
  static bool hasSeen() {
    try {
      final box = Hive.box(_boxName);
      return box.get(_seenKey, defaultValue: false) as bool;
    } catch (_) {
      return true;
    }
  }

  /// Mark the spotlight as seen. Safe to call multiple times.
  static Future<void> markSeen() async {
    try {
      final box = Hive.box(_boxName);
      await box.put(_seenKey, true);
    } catch (_) {
      // Best-effort persistence. If Hive isn't available the user will see
      // the spotlight once more on the next launch, which is acceptable.
    }
  }

  /// Show the spotlight if it hasn't been seen yet. Caller must pass a
  /// `GlobalKey` attached to the target icon widget. The overlay is
  /// inserted into the nearest `Overlay`, painted around the target's
  /// `RenderBox`, and removed automatically.
  static Future<void> maybeShow(
    BuildContext context,
    GlobalKey targetKey,
  ) async {
    if (_inFlight) return;
    if (hasSeen()) return;
    _inFlight = true;

    // Give the AppBar one frame + a small visual settle to lay itself out
    // before we measure the target. Without this the RenderBox can be null
    // on cold start.
    await Future.delayed(_showDelay);
    if (!context.mounted) {
      _inFlight = false;
      return;
    }

    final renderBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      _inFlight = false;
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      _inFlight = false;
      return;
    }

    final targetPos = renderBox.localToGlobal(Offset.zero);
    final targetSize = renderBox.size;
    final targetCenter = Rect.fromLTWH(
      targetPos.dx,
      targetPos.dy,
      targetSize.width,
      targetSize.height,
    ).center;
    final holeRadius = (targetSize.shortestSide / 2) + 10;

    late OverlayEntry entry;
    Timer? autoDismiss;

    void dismiss() {
      autoDismiss?.cancel();
      try {
        entry.remove();
      } catch (_) {}
      markSeen();
      _inFlight = false;
    }

    entry = OverlayEntry(
      builder: (ctx) {
        return _SpotlightOverlay(
          holeCenter: targetCenter,
          holeRadius: holeRadius,
          onDismiss: dismiss,
        );
      },
    );

    overlay.insert(entry);
    autoDismiss = Timer(_autoDismiss, dismiss);
  }
}

class _SpotlightOverlay extends StatefulWidget {
  final Offset holeCenter;
  final double holeRadius;
  final VoidCallback onDismiss;

  const _SpotlightOverlay({
    required this.holeCenter,
    required this.holeRadius,
    required this.onDismiss,
  });

  @override
  State<_SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<_SpotlightOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fade;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fade.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final calloutTop = widget.holeCenter.dy + widget.holeRadius + 14;
    // Callout right-aligns with a small margin so it points at the icon
    // (icons live on the right of the AppBar in this app).
    final calloutWidth =
        screenW * 0.78 > 360 ? 360.0 : screenW * 0.78;
    final calloutRight = (screenW - widget.holeCenter.dx) - 22;

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // Backdrop with a hole. Tap-to-dismiss everywhere.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: CustomPaint(
              size: mq.size,
              painter: _SpotlightPainter(
                holeCenter: widget.holeCenter,
                holeRadius: widget.holeRadius,
              ),
            ),
          ),
          // Pulsing ring on the cut-out — secondary "look here" cue.
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final scale = 1.0 + (_pulse.value * 0.22);
              final opacity = 0.55 - (_pulse.value * 0.45);
              return Positioned(
                left: widget.holeCenter.dx -
                    (widget.holeRadius * scale),
                top: widget.holeCenter.dy -
                    (widget.holeRadius * scale),
                width: widget.holeRadius * 2 * scale,
                height: widget.holeRadius * 2 * scale,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kPrimaryColor.withOpacity(opacity),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Callout card.
          Positioned(
            top: calloutTop,
            right: calloutRight,
            width: calloutWidth,
            child: _CalloutCard(onDismiss: widget.onDismiss),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Offset holeCenter;
  final double holeRadius;

  _SpotlightPainter({required this.holeCenter, required this.holeRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.62);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: holeCenter, radius: holeRadius));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.holeCenter != holeCenter || old.holeRadius != holeRadius;
}

class _CalloutCard extends StatelessWidget {
  final VoidCallback onDismiss;
  const _CalloutCard({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          SizeConfig.imageSizeMultiplier * 4,
          SizeConfig.heightMultiplier * 1.8,
          SizeConfig.imageSizeMultiplier * 4,
          SizeConfig.heightMultiplier * 1.6,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: SizeConfig.imageSizeMultiplier * 8,
                  height: SizeConfig.imageSizeMultiplier * 8,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.insights_outlined,
                    color: kPrimaryColor,
                    size: SizeConfig.imageSizeMultiplier * 4.5,
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2.5),
                Expanded(
                  child: Text(
                    'New: customer insights',
                    style: TextStyle(
                      color: const Color(0xFF1A1F2B),
                      fontSize: SizeConfig.textMultiplier * 1.8,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.0),
            Text(
              "Tap the chart icon to see this customer's repayment "
              "behaviour, totals and a full report — derived from their "
              "ledger.",
              style: TextStyle(
                color: const Color(0xFF4B5563),
                fontSize: SizeConfig.textMultiplier * 1.45,
                height: 1.4,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: kPrimaryColor,
                  textStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.55,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
