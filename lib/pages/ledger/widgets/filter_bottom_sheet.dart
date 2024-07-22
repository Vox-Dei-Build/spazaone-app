import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({
    super.key,
  });

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
    _tempReminderDateFilter = List.from(dataModel.reminderDateFilter);
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
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5.0),
              const Divider(color: kHighLightColor),
              const Text(
                'Reminder Date',
                style: TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12.0),
              SizedBox(
                height: 38.0,
                child: ListView.separated(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: value.reminderDateFilter.length,
                  itemBuilder: (context, index) {
                    final isSelected = value.reminderDateFilter[index][1];
                    final title = value.reminderDateFilter[index][0];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _tempReminderDateFilter[index][1] =
                              !_tempReminderDateFilter[index][1];
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Center(
                          child: Row(
                            children: [
                              Text(title),
                              isSelected
                                  ? const Padding(
                                      padding: EdgeInsets.only(left: 2.0),
                                      child: Icon(
                                        Icons.check,
                                        color: Colors.green,
                                        size: 20.0,
                                      ),
                                    )
                                  : const SizedBox.shrink()
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const SizedBox(width: 15.0);
                  },
                ),
              ),
              const SizedBox(height: 25.0),
              const Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
              ListView.separated(
                itemCount: value.sortByFilter.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  return RadioListTile(
                    contentPadding: const EdgeInsets.all(0),
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -2,
                    ),
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
                  return const SizedBox(
                    width: 15.0,
                  );
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
              const SizedBox(height: 10.0)
            ],
          ),
        );
      },
    );
  }
}
