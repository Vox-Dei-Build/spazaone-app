import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

/// Step 1 of the Create Template wizard.
///
/// Asks the merchant for a friendly **display name** (what they see in lists)
/// and shows a live **internal ID** preview underneath that's auto-derived to
/// match WhatsApp's strict naming rules (lowercase, digits, underscores). A
/// rules checklist ticks live as they type, plus a debounced duplicate-name
/// check against existing templates.
class BasicInfoStep extends StatefulWidget {
  /// Controller for the user-facing display name.
  final TextEditingController displayNameController;

  /// Pure function to sanitise the display name into the WhatsApp ID.
  /// Provided by the parent so the same logic is used at save time.
  final String Function(String) sanitize;

  /// Userid for scoping the duplicate name lookup.
  final String userId;

  /// Optional doc id to exclude from duplicate checks (e.g. when editing).
  final String? excludeTemplateId;

  /// Notifies the parent whenever the sanitised name changes — used so the
  /// parent can keep its own state in sync (and disable Next on duplicate).
  final void Function(String sanitized, bool isDuplicate)? onSanitizedChanged;

  const BasicInfoStep({
    super.key,
    required this.displayNameController,
    required this.sanitize,
    required this.userId,
    this.excludeTemplateId,
    this.onSanitizedChanged,
  });

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  static const int _maxLength = 64;

  String _sanitized = '';
  bool _checkingDuplicate = false;
  bool _isDuplicate = false;
  int _checkToken = 0;

  @override
  void initState() {
    super.initState();
    _sanitized = widget.sanitize(widget.displayNameController.text);
    widget.displayNameController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.displayNameController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final next = widget.sanitize(widget.displayNameController.text);
    if (next == _sanitized) return;
    setState(() {
      _sanitized = next;
      _isDuplicate = false;
    });
    widget.onSanitizedChanged?.call(_sanitized, false);
    _scheduleDuplicateCheck(next);
  }

  Future<void> _scheduleDuplicateCheck(String name) async {
    final token = ++_checkToken;
    if (name.isEmpty) {
      setState(() => _checkingDuplicate = false);
      return;
    }
    setState(() => _checkingDuplicate = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (token != _checkToken || !mounted) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('messagingTemplates')
          .where('userId', isEqualTo: widget.userId)
          .where('name', isEqualTo: name)
          .limit(2)
          .get();
      if (token != _checkToken || !mounted) return;
      final dup = snap.docs.any((d) => d.id != widget.excludeTemplateId);
      setState(() {
        _isDuplicate = dup;
        _checkingDuplicate = false;
      });
      widget.onSanitizedChanged?.call(_sanitized, dup);
    } catch (_) {
      if (token != _checkToken || !mounted) return;
      setState(() => _checkingDuplicate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = widget.displayNameController.text;
    final hasInput = raw.trim().isNotEmpty;

    final rules = <_Rule>[
      _Rule(
        label: 'At least 1 character',
        ok: _sanitized.isNotEmpty,
      ),
      _Rule(
        label: 'No more than $_maxLength characters',
        ok: _sanitized.length <= _maxLength,
      ),
      _Rule(
        label: 'Unique (not used by another template)',
        ok: hasInput && !_checkingDuplicate && !_isDuplicate,
        loading: _checkingDuplicate,
      ),
    ];

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 3,
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      children: [
        Text(
          'Name your template',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'A friendly name to help you find this template later. We\'ll generate a WhatsApp-compatible ID for you.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),

        TextFormField(
          controller: widget.displayNameController,
          autofocus: true,
          maxLength: _maxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Display name',
            hintText: 'e.g. Summer Sale 2026',
            border: const OutlineInputBorder(),
            counterText: '${raw.length} / $_maxLength',
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter a name';
            }
            if (_sanitized.isEmpty) {
              return 'Use letters or numbers — punctuation alone won\'t work';
            }
            if (_isDuplicate) {
              return 'You already have a template with this name';
            }
            return null;
          },
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 12),

        // Live ID preview
        _IdPreview(
          sanitized: _sanitized,
          checking: _checkingDuplicate,
          isDuplicate: _isDuplicate,
        ),

        const SizedBox(height: 16),

        // Rules checklist
        Text(
          'Requirements',
          style:
              theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ...rules.map((r) => _RuleRow(rule: r)),

        const SizedBox(height: 16),

        // Examples (collapsible)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
          title: Text(
            'See good examples',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          children: const [
            _ExampleRow(input: 'Summer Sale 2026', output: 'summer_sale_2026'),
            _ExampleRow(input: 'Weekly Specials', output: 'weekly_specials'),
            _ExampleRow(
                input: 'New Stock — Chicken!', output: 'new_stock_chicken'),
          ],
        ),
      ],
    );
  }
}

class _Rule {
  final String label;
  final bool ok;
  final bool loading;
  _Rule({required this.label, required this.ok, this.loading = false});
}

class _RuleRow extends StatelessWidget {
  final _Rule rule;
  const _RuleRow({required this.rule});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget icon;
    Color color;
    if (rule.loading) {
      icon = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      color = theme.disabledColor;
    } else if (rule.ok) {
      icon = const Icon(Icons.check_circle, size: 16, color: Colors.green);
      color = Colors.green.shade700;
    } else {
      icon = Icon(Icons.radio_button_unchecked,
          size: 16, color: theme.disabledColor);
      color = theme.disabledColor;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Text(rule.label,
              style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _IdPreview extends StatelessWidget {
  final String sanitized;
  final bool checking;
  final bool isDuplicate;

  const _IdPreview({
    required this.sanitized,
    required this.checking,
    required this.isDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = sanitized.isEmpty;
    final color = isDuplicate
        ? theme.colorScheme.error
        : empty
            ? theme.disabledColor
            : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.code, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(color: color),
                children: [
                  const TextSpan(text: 'Will be saved as: '),
                  TextSpan(
                    text: empty ? '—' : sanitized,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (checking)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _ExampleRow extends StatelessWidget {
  final String input;
  final String output;
  const _ExampleRow({required this.input, required this.output});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(input, style: theme.textTheme.bodySmall),
          ),
          const Icon(Icons.arrow_forward, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              output,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
