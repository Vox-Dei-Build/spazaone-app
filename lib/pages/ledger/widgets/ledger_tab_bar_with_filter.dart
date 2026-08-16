import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';

class LedgerTabBarWithFilter extends StatelessWidget {
  final ValueNotifier<int> tabIndexNotifier;

  const LedgerTabBarWithFilter({Key? key, required this.tabIndexNotifier})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WorkspaceSectionTabs(
      onSelected: (index) => tabIndexNotifier.value = index,
      tabs: const [
        WorkspaceSectionTab(
          label: 'Customers',
          semanticLabel: 'Customers list',
        ),
        WorkspaceSectionTab(
          label: 'Activity',
          semanticLabel: 'Customer activity by date',
        ),
        WorkspaceSectionTab(
          label: 'Summary',
          semanticLabel: 'Customer account summary',
        ),
      ],
    );
  }
}
