import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// Shared business-type/category choices, with room for translated or scaled labels.
class BusinessChoiceList extends StatelessWidget {
  const BusinessChoiceList({
    super.key,
    required this.choices,
    required this.assetFolder,
    required this.onSelected,
  });

  final List<dynamic> choices;
  final String assetFolder;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(SpazaSpace.lg),
        itemCount: choices.length,
        separatorBuilder: (_, __) => const SizedBox(height: SpazaSpace.sm),
        itemBuilder: (context, index) {
          final choice = choices[index];
          final title = choice[0] as String;
          final selected = choice[2] == true;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              selected: selected,
              selectedTileColor: SpazaColors.selected,
              selectedColor: SpazaColors.heading,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: SpazaSpace.lg,
                vertical: SpazaSpace.sm,
              ),
              leading: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 44,
                  child: Image.asset('$assetFolder/${choice[1]}.png'),
                ),
              ),
              title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
              trailing: Icon(selected
                  ? Icons.check_circle_outline_rounded
                  : SpazaIcons.next),
              onTap: () => onSelected(title),
            ),
          );
        },
      );
}
