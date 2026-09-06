import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// A compact reminder of whose account is being changed.
class CustomerFormHeader extends StatelessWidget {
  const CustomerFormHeader({super.key, required this.customerName});

  final String customerName;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Customer $customerName',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: SpazaSpace.lg),
          padding: const EdgeInsets.symmetric(
            horizontal: SpazaSpace.md,
            vertical: SpazaSpace.sm,
          ),
          decoration: BoxDecoration(
            color: SpazaColors.selected,
            borderRadius: BorderRadius.circular(SpazaRadius.control),
          ),
          child: Row(
            children: [
              const Icon(
                SpazaIcons.customers,
                color: SpazaColors.heading,
                size: 20,
              ),
              const SizedBox(width: SpazaSpace.sm),
              Expanded(
                child: Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: SpazaColors.heading,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}
