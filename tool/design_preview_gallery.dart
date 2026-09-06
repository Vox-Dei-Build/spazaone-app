import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

/// Searchable index of production presentation assembled with local example data.
class DesignPreviewGallery extends StatefulWidget {
  const DesignPreviewGallery(
      {super.key, required this.groups, required this.onOpen});
  final Map<String, Map<String, WidgetBuilder>> groups;
  final void Function(String label, WidgetBuilder builder) onOpen;
  @override
  State<DesignPreviewGallery> createState() => _DesignPreviewGalleryState();
}

class _DesignPreviewGalleryState extends State<DesignPreviewGallery> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total =
        widget.groups.values.fold<int>(0, (n, group) => n + group.length);
    final visible = <String, List<MapEntry<String, WidgetBuilder>>>{
      for (final group in widget.groups.entries)
        group.key: group.value.entries
            .where((screen) => '${group.key} ${screen.key}'
                .toLowerCase()
                .contains(_query.toLowerCase()))
            .toList(),
    };
    return Scaffold(
      appBar: const CustomAppBar(title: 'Explore the app'),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('preview-gallery-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('$total screens in the approachable style',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'Browse layouts and try the controls with example data. Nothing is sent, paid or saved to an account.'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('preview-gallery-search'),
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Find a screen',
                prefixIcon: Icon(SpazaIcons.search),
              ),
            ),
            const SizedBox(height: 8),
            for (final group in visible.entries)
              if (group.value.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 12),
                  child: Text(group.key, style: theme.textTheme.titleSmall),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final screen in group.value)
                      ListTile(
                        key: ValueKey('preview-gallery-${screen.key}'),
                        title: Text(screen.key),
                        trailing: const Icon(SpazaIcons.next),
                        onTap: () => widget.onOpen(screen.key, screen.value),
                      ),
                  ]),
                ),
              ],
            if (visible.values.every((group) => group.isEmpty))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                    'No screens match. Try “product”, “customer” or “shop”.'),
              ),
          ],
        ),
      ),
    );
  }
}
