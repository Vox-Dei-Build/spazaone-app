import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/pages/settings/widgets/custom_switch.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  static const id = '/securityPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Security'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding20Horizontal,
          child: Consumer<AppModel>(
            builder: (context, value, child) {
              return Column(
                children: [
                  SettingTile(
                    onTap: () {},
                    icon: Icons.lock,
                    title: 'Change Security PIN',
                  ),
                  SettingTile(
                    icon: Icons.phonelink_lock,
                    title: 'App Lock',
                    trailing: CustomSwitch(
                      onChanged: (p0) => value.toggleSwitch(SwitchType.appLock),
                      value: value.isAppLockEnabled,
                    ),
                  ),
                  SettingTile(
                    icon: Icons.credit_score,
                    title: 'Payment Password',
                    trailing: CustomSwitch(
                      onChanged: (p0) =>
                          value.toggleSwitch(SwitchType.paymentPassword),
                      value: value.isPaymentPasswordEnabled,
                    ),
                  ),
                  SettingTile(
                    icon: Icons.fingerprint,
                    title: 'Fingerprint Unlock',
                    trailing: CustomSwitch(
                      onChanged: (p0) =>
                          value.toggleSwitch(SwitchType.fingerPrint),
                      value: value.isFingerprintEnabled,
                    ),
                  ),
                  SettingTile(
                    onTap: () {},
                    icon: Icons.logout,
                    title: 'Sign out from all devices',
                  ),
                  SettingTile(
                    onTap: () {},
                    icon: Icons.power_settings_new,
                    title: 'Sign Out',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
