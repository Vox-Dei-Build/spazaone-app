import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';

class CustomerSelectionStep extends StatelessWidget {
  final bool allCustomers;

  /// Channel-filtered customer list. The wizard now pre-filters
  /// based on the selected channels (WhatsApp-only hides known
  /// not-WA customers; SMS-only and Both show everyone with a
  /// number). See [PromotionsViewModel.filterCustomersForChannels].
  final List<Map<String, dynamic>> customers;
  final Set<String> selectedCustomerIds;
  final ValueChanged<bool> onAllCustomersChanged;
  final ValueChanged<String> onCustomerToggle;
  final VoidCallback onAddCustomer;

  /// Number of customers filtered out of the *full* numbered-customer
  /// list because they have no phone number. Shown as an inline
  /// notice so the merchant understands why their customer count
  /// here can be smaller than on the Ledger page.
  final int hiddenWithoutNumberCount;

  /// PAS-WA-03: which channels the merchant selected on step 1. The
  /// banner copy changes per combination so the merchant knows
  /// exactly which customers are eligible and why the count differs
  /// from what they see on the ledger.
  final bool sendWhatsApp;
  final bool sendSMS;

  /// PAS-WA-03: number of customers excluded by the channel filter
  /// because they are not WhatsApp-reachable (only relevant when
  /// WhatsApp is the only selected channel).
  final int hiddenNotWhatsAppCount;

  /// PAS-WA-03: number of customers included in the list whose
  /// WhatsApp status hasn't been confirmed yet. The send path will
  /// do a live check before charging, but we surface this here so
  /// the merchant knows some of these may not actually receive.
  final int unknownWhatsAppCount;
  final String heading;
  final String allCustomersLabel;
  final String? recommendationText;

  const CustomerSelectionStep({
    Key? key,
    required this.allCustomers,
    required this.customers,
    required this.selectedCustomerIds,
    required this.onAllCustomersChanged,
    required this.onCustomerToggle,
    required this.onAddCustomer,
    this.hiddenWithoutNumberCount = 0,
    this.sendWhatsApp = true,
    this.sendSMS = false,
    this.hiddenNotWhatsAppCount = 0,
    this.unknownWhatsAppCount = 0,
    this.heading = 'Choose customers',
    this.allCustomersLabel = 'All customers',
    this.recommendationText,
  }) : super(key: key);

  /// Only surface channel information when it changes who can receive the
  /// promotion. The selected channel controls already communicate the normal
  /// case, so repeating it here adds noise without helping a decision.
  String? _channelBannerText() {
    if (sendWhatsApp && sendSMS) {
      return null;
    }
    if (sendWhatsApp && !sendSMS) {
      final parts = <String>[];
      if (hiddenNotWhatsAppCount > 0) {
        parts.add(
          hiddenNotWhatsAppCount == 1
              ? '1 customer is not on WhatsApp.'
              : '$hiddenNotWhatsAppCount customers are not on WhatsApp.',
        );
      }
      if (unknownWhatsAppCount > 0) {
        parts.add(
          unknownWhatsAppCount == 1
              ? '1 number will be checked before sending.'
              : '$unknownWhatsAppCount numbers will be checked before sending.',
        );
      }
      return parts.isEmpty ? null : parts.join(' ');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(heading,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Expanded(
            child: _EmptyCustomerSelection(
              hiddenWithoutNumberCount: hiddenWithoutNumberCount,
              hiddenNotWhatsAppCount: hiddenNotWhatsAppCount,
              sendWhatsApp: sendWhatsApp,
              sendSMS: sendSMS,
              onAddCustomer: onAddCustomer,
            ),
          ),
        ],
      );
    }

    final channelBanner = _channelBannerText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(heading,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        if (recommendationText != null)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2,
              vertical: SizeConfig.heightMultiplier * 0.5,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recommendationText!,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (channelBanner != null)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2,
              vertical: SizeConfig.heightMultiplier * 0.5,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channelBanner,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (hiddenWithoutNumberCount > 0)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2,
              vertical: SizeConfig.heightMultiplier * 0.5,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hiddenWithoutNumberCount == 1
                          ? '1 customer without a phone number is not shown.'
                          : '$hiddenWithoutNumberCount customers without phone numbers are not shown.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            value: allCustomers,
            onChanged: (_) => onAllCustomersChanged(!allCustomers),
            title: Text(allCustomersLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18))),
        Expanded(
          child: ListView.builder(
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final customer = customers[index];
              final name = customer['name'] ?? '';
              final number = customer['number'] ?? '';
              final balance = customer['balance']?.toDouble() ?? 0.0;
              final id = customer['id'];
              final profileImageUrl = customer['profileImageUrl'];
              // PAS-UI-02: use the customer's real NPA flag rather
              // than hardcoding `true` for every row (which was a
              // copy-paste bug — the indicator is now hidden by
              // default app-wide via `showNPAIndicator: false`, but
              // passing the wrong value was still inconsistent with
              // every other avatar usage in the app).
              final bool? isNPA = customer['isNPA'] as bool?;

              final isSelected = selectedCustomerIds.contains(id);

              return CheckboxListTile(
                value: allCustomers ? true : isSelected,
                onChanged: allCustomers
                    ? null // disable taps when “All” is on
                    : (_) => onCustomerToggle(id),
                title: Row(
                  children: [
                    // PAS-UI-02: align with the canonical avatar
                    // usage (see `TransactionTile`): pass radius and
                    // `showNPAIndicator: false` so the phone-status
                    // pill is the only overlay — same visual as the
                    // ledger, customer detail header, etc.
                    profilePicture(
                      context,
                      name,
                      profileImageUrl,
                      number,
                      isNPA,
                      showNPAIndicator: false,
                      radius: SizeConfig.heightMultiplier * 2.6,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      CurrencyUtil.format(balance),
                      style: TextStyle(
                        fontSize: 13,
                        color: balance >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyCustomerSelection extends StatelessWidget {
  const _EmptyCustomerSelection({
    required this.hiddenWithoutNumberCount,
    required this.hiddenNotWhatsAppCount,
    required this.sendWhatsApp,
    required this.sendSMS,
    required this.onAddCustomer,
  });

  final int hiddenWithoutNumberCount;
  final int hiddenNotWhatsAppCount;
  final bool sendWhatsApp;
  final bool sendSMS;
  final VoidCallback onAddCustomer;

  String get _message {
    if (hiddenWithoutNumberCount > 0) {
      final count = hiddenWithoutNumberCount;
      return count == 1
          ? '1 customer needs a mobile number. Update them in Customers or add someone new.'
          : '$count customers need mobile numbers. Update them in Customers or add someone new.';
    }
    if (sendWhatsApp && !sendSMS && hiddenNotWhatsAppCount > 0) {
      return 'Your saved customers cannot receive this WhatsApp promotion. Add someone new or choose SMS.';
    }
    return 'Add a customer with a mobile number to continue.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          key: const Key('promotion-empty-customers'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No customers ready',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('promotion-add-customer'),
              onPressed: onAddCustomer,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add customer'),
            ),
          ],
        ),
      ),
    );
  }
}
