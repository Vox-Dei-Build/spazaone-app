import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';

enum CoachmarkPosition { top, bottom }

class ActivationCoachmark extends StatefulWidget {
  const ActivationCoachmark({
    super.key,
    required this.userId,
    required this.coachmarkKey,
    required this.title,
    required this.message,
    required this.child,
    this.enabled = true,
    this.position = CoachmarkPosition.top,
    this.icon = Icons.touch_app_outlined,
    this.accentColor,
  });

  final String userId;
  final String coachmarkKey;
  final String title;
  final String message;
  final Widget child;
  final bool enabled;
  final CoachmarkPosition position;
  final IconData icon;
  final Color? accentColor;

  @override
  State<ActivationCoachmark> createState() => _ActivationCoachmarkState();
}

class _ActivationCoachmarkState extends State<ActivationCoachmark> {
  bool _visible = false;

  String get _storageKey =>
      'activation_coachmark:${widget.userId}:${widget.coachmarkKey}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ActivationCoachmark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.coachmarkKey != widget.coachmarkKey ||
        oldWidget.enabled != widget.enabled) {
      _load();
    }
  }

  void _load() {
    if (!widget.enabled || widget.userId.isEmpty) {
      _visible = false;
      return;
    }
    final seen = Hive.box('appBox').get(_storageKey, defaultValue: false);
    _visible = seen != true;
  }

  Future<void> _dismiss() async {
    await Hive.box('appBox').put(_storageKey, true);
    if (!mounted) return;
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;

    final bubble = _CoachmarkBubble(
      title: widget.title,
      message: widget.message,
      icon: widget.icon,
      accentColor: widget.accentColor ?? Colors.green.shade700,
      onDismiss: _dismiss,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: widget.position == CoachmarkPosition.top
          ? [
              bubble,
              const SizedBox(height: 8),
              widget.child,
            ]
          : [
              widget.child,
              const SizedBox(height: 8),
              bubble,
            ],
    );
  }
}

class _CoachmarkBubble extends StatelessWidget {
  const _CoachmarkBubble({
    required this.title,
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.black87,
                    height: 1.25,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
