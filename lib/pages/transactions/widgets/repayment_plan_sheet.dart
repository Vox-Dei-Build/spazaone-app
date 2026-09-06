import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/currency_util.dart';

class RepaymentPlanDraft {
  const RepaymentPlanDraft({
    required this.totalAmountMinor,
    required this.installmentAmountMinor,
    required this.cadence,
    required this.startAtMs,
  });

  final int totalAmountMinor;
  final int installmentAmountMinor;
  final String cadence;
  final int startAtMs;
}

class RepaymentPlanSheet extends StatefulWidget {
  const RepaymentPlanSheet({
    super.key,
    required this.customerName,
    required this.outstandingAmountMinor,
  });

  final String customerName;
  final int outstandingAmountMinor;

  @override
  State<RepaymentPlanSheet> createState() => _RepaymentPlanSheetState();
}

class _RepaymentPlanSheetState extends State<RepaymentPlanSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _totalController;
  final TextEditingController _installmentController = TextEditingController();
  String _cadence = 'weekly';
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(
      text: (widget.outstandingAmountMinor / 100).toStringAsFixed(2),
    );
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
  }

  @override
  void dispose() {
    _totalController.dispose();
    _installmentController.dispose();
    super.dispose();
  }

  int? _minorUnits(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final rands = int.parse(match.group(1)!);
    final decimals = (match.group(2) ?? '').padRight(2, '0');
    return rands * 100 + (decimals.isEmpty ? 0 : int.parse(decimals));
  }

  String? _totalError(String? value) {
    final amount = _minorUnits(value ?? '');
    if (amount == null || amount <= 0) return 'Enter a valid plan total.';
    if (amount > widget.outstandingAmountMinor) {
      return 'The plan cannot exceed the amount owing.';
    }
    return null;
  }

  String? _installmentError(String? value) {
    final installment = _minorUnits(value ?? '');
    final total = _minorUnits(_totalController.text);
    if (installment == null || installment <= 0) {
      return 'Enter a valid installment amount.';
    }
    if (total != null && installment > total) {
      return 'The installment cannot exceed the plan total.';
    }
    return null;
  }

  Future<void> _pickStartDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(today.year, today.month, today.day + 1),
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day, 9);
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      RepaymentPlanDraft(
        totalAmountMinor: _minorUnits(_totalController.text)!,
        installmentAmountMinor: _minorUnits(_installmentController.text)!,
        cadence: _cadence,
        startAtMs: _startDate.millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Set repayment plan', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '${widget.customerName} owes ${CurrencyUtil.format(widget.outstandingAmountMinor / 100)}. Choose a plan they can pay securely from WhatsApp.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SpazaColors.muted,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('repayment-plan-total'),
                controller: _totalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount covered by plan',
                  prefixText: 'R ',
                ),
                validator: _totalError,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('repayment-plan-installment'),
                controller: _installmentController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount per installment',
                  prefixText: 'R ',
                ),
                validator: _installmentError,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                itemHeight: null,
                key: const Key('repayment-plan-cadence'),
                value: _cadence,
                decoration: const InputDecoration(
                  labelText: 'Payment frequency',
                ),
                items: const [
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(
                    value: 'fortnightly',
                    child: Text('Every two weeks'),
                  ),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _cadence = value);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('First payment date'),
                subtitle:
                    Text(DateFormat('EEE, d MMM yyyy').format(_startDate)),
                trailing: TextButton(
                  onPressed: _pickStartDate,
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('repayment-plan-create'),
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: SpazaColors.action,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Create plan'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
