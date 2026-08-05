import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/common/app_model.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  static const id = '/LanguagePage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Language'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: Consumer<AppModel>(
            builder: (context, value, child) {
              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(0),
                    itemCount: value.languageList.length,
                    itemBuilder: (context, index) {
                      final String language = value.languageList[index][0];
                      final bool isSelected = value.languageList[index][1];
                      return ListTile(
                        onTap: () {
                          value.updateAppLanguage(language);
                          Navigator.pop(context);
                        },
                        leading: Text(
                          language,
                          style: const TextStyle(fontSize: 16.0),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: kPrimaryColor)
                            : null,
                      );
                    },
                    separatorBuilder: (context, index) {
                      return const Divider(
                        height: 10.0,
                        color: kHighLightColor,
                      );
                    },
                  ),
                  const Divider(
                    height: 10.0,
                    color: kHighLightColor,
                  ),
                  const SizedBox(height: 10.0),
                  const Text('Choose Spaza One App Language')
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
