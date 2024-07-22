import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

class SavingButtonWidget extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final ValueNotifier<bool> isProcessing;
  final String selectedService;
  final String selectedAccountType;
  final Function(BuildContext context, String selectedService,
      String selectedAccountType) onSave;

  const SavingButtonWidget({
    Key? key,
    required this.formKey,
    required this.isProcessing,
    required this.selectedService,
    required this.selectedAccountType,
    required this.onSave,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomButton(
          title: 'Save',
          onTap: isProcessing.value
              ? () => null
              : () async {
                  if (formKey.currentState!.validate()) {
                    formKey.currentState!.save();
                    onSave(context, selectedService, selectedAccountType);
                  }
                },
          margin: const EdgeInsets.fromLTRB(10, 20, 10, 10),
          icon: Icons.save,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: isProcessing,
          builder: (context, isProcessing, child) {
            return isProcessing
                ? CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                : SizedBox.shrink(); // Invisible when not processing
          },
        ),
      ],
    );
  }
}
