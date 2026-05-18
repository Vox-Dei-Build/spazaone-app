import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/logo_display.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/widgets/private_region.dart';

Widget buildLoginUI(BuildContext context, AuthViewModel authViewModel) {
  SizeConfig().init(context);

  return Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 6,
              vertical: SizeConfig.heightMultiplier * 3),
          child: Form(
            key: authViewModel.formKey,
            child: Column(
              children: <Widget>[
                SizedBox(height: SizeConfig.heightMultiplier * 5),
                const LogoDisplay(),
                SizedBox(height: SizeConfig.heightMultiplier * 6),
                // PAS-AUTH-01: Make it unambiguous that mobile number is the
                // primary auth method and an SMS code is on the way. Users
                // were getting stuck staring at a lone phone field.
                Text(
                  'Sign in with your mobile number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2.4,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 1),
                Text(
                  "We'll text you a 6-digit code to confirm it's you. "
                  'No password needed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.6,
                    color: Colors.grey[700],
                    height: 1.3,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 3),
                PrivateRegion(
                  child: CustomTextField(
                    label: 'Mobile Number',
                    hintText: 'e.g. 082 123 4567',
                    prefixIcon: Icons.phone,
                    controller: authViewModel.mobileNoController,
                    textInputType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'This field is required';
                      }
                      if (!isValidSAPhoneNumber(value)) {
                        return kSAOnlyPhoneMessage;
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                ValueListenableBuilder<bool>(
                  valueListenable: authViewModel.isLoading,
                  builder: (context, isLoading, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: 'Login',
                          onTap: isLoading
                              ? () {}
                              : () {
                                  if (authViewModel.formKey.currentState!
                                      .validate()) {
                                    authViewModel.handleLogin(context);
                                  }
                                },
                          color: Colors.green,
                          icon: Icons.login,
                          fontSize: SizeConfig.textMultiplier * 2,
                        ),
                        if (isLoading)
                          const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)),
                      ],
                    );
                  },
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                CustomButton(
                  title: 'Register',
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/registerPage');
                  },
                  color: Colors.green,
                  icon: Icons.app_registration,
                  fontSize: SizeConfig.textMultiplier * 2,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
