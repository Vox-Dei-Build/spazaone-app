import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';

/// PAS-UX-10: UpdateNumberPage is a stub.
///
/// The "Verify Mobile" button is wired to `() {}` and there is no
/// supporting view-model, OTP flow, data-migration job, or backend
/// hook. The page also has no entry point in Settings or anywhere
/// else in the app — it is reachable only via the
/// `/updateNumberPage` route, which is registered in `main.dart` for
/// historical reasons.
///
/// Audit decision: do not remove the route (could break a deep
/// link), do not surface the page in Settings (it would lie to the
/// merchant), and do not precache its asset (waste of startup
/// work). Re-enable when the OTP/data-migration backend exists.
class UpdateNumberPage extends StatelessWidget {
  const UpdateNumberPage({super.key});

  static const id = '/updateNumberPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Update Number'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: Column(
            children: [
              const SizedBox(height: 70.0),
              Image.asset(
                'assets/images/update_number.png',
                width: 300,
              ),
              const SizedBox(height: 30.0),
              const BulletPoint(
                text:
                    'Changing number will migrate all your data to the new number.',
              ),
              const BulletPoint(
                text: 'Make sure, you are able to reeive SMS on new number',
              ),
              const BulletPoint(
                text: 'An OTP will be send on 80XXXXXXX6 to verify the user.',
              ),
              const SizedBox(height: 25.0),
              CustomButton(
                width: 200.0,
                title: 'Verify Mobile',
                onTap: () {},
              )
            ],
          ),
        ),
      ),
    );
  }
}

class BulletPoint extends StatelessWidget {
  const BulletPoint({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10.0,
        vertical: 5.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 8.0,
            width: 8.0,
            margin: const EdgeInsets.only(top: 6.0),
            decoration: const BoxDecoration(
              color: Color(0xff424242),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5.0),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Make sure, you are able to recieve SMS on new number