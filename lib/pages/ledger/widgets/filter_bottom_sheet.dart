import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  _FilterBottomSheetState createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late List<List> _tempReminderDateFilter;
  late String _tempSortByFilter;

  @override
  void initState() {
    super.initState();
    final dataModel = context.read<AppModel>();
    _tempReminderDateFilter = dataModel.reminderDateFilter
        .map((filter) => List<dynamic>.from(filter))
        .toList();
    _tempSortByFilter = dataModel.selectedSortByFilter;
  }

  @override
  Widget build(BuildContext context) {
    final dataModel = Provider.of<AppModel>(context, listen: false);
    return Consumer<AppModel>(
      builder: (context, value, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20.0),
              const Text(
                'Filter',
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5.0),
              const Divider(color: kHighLightColor),
              const Text(
                'Reminder Date',
                style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12.0),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (var index = 0;
                      index < value.reminderDateFilter.length;
                      index++)
                    Builder(builder: (context) {
                      final isSelected = _tempReminderDateFilter[index][1];
                      final title = _tempReminderDateFilter[index][0];
                      return Semantics(
                        button: true,
                        selected: isSelected,
                        label: '$title reminder filter',
                        child: Material(
                          color: isSelected
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12.0),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12.0),
                            onTap: () {
                              setState(() {
                                final next = !_tempReminderDateFilter[index][1];
                                for (final filter in _tempReminderDateFilter) {
                                  filter[1] = false;
                                }
                                _tempReminderDateFilter[index][1] = next;
                              });
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(title),
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.check,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 25.0),
              const Text(
                'Sort By',
                style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w500),
              ),
              ListView.separated(
                itemCount: value.sortByFilter.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  return RadioListTile(
                    contentPadding: const EdgeInsets.all(0),
                    title: Text(value.sortByFilter[index]),
                    value: value.sortByFilter[index],
                    groupValue: _tempSortByFilter,
                    onChanged: (value) {
                      setState(() {
                        _tempSortByFilter = value!;
                      });
                    },
                  );
                },
                separatorBuilder: (context, index) {
                  return const SizedBox(width: 15.0);
                },
              ),
              const Divider(color: kHighLightColor),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CustomButton(
                    height: 35.0,
                    width: 80.0,
                    fontSize: 14.0,
                    onTap: () {
                      Navigator.pop(context);
                    },
                    title: 'Cancel',
                    color: Colors.grey.shade800,
                  ),
                  CustomButton(
                    height: 35.0,
                    width: 80.0,
                    fontSize: 14.0,
                    onTap: () {
                      value.resetFilter();
                      Navigator.pop(context);
                    },
                    title: 'Reset',
                    color: Colors.grey.shade800,
                  ),
                  CustomButton(
                    height: 35.0,
                    width: 80.0,
                    fontSize: 14.0,
                    onTap: () {
                      dataModel.updateFromTemporaryFilters(
                        _tempReminderDateFilter,
                        _tempSortByFilter,
                      );
                      Navigator.pop(context);
                    },
                    title: 'Apply',
                  ),
                ],
              ),
              const SizedBox(height: 10.0),
            ],
          ),
        );
      },
    );
  }
}
