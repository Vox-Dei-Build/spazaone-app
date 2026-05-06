import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/logo_display.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:pasella/widgets/private_region.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);
  static const id = '/registerPage';

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late AuthViewModel authViewModel;
  late String? referrerUserId;

  @override
  void initState() {
    super.initState();
    authViewModel = AuthViewModel();
    loadInitialData();
  }

  void loadInitialData() async {
    var box = Hive.box('deepLinkBox');
    referrerUserId = box.get('referrerUserId', defaultValue: null);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 6),
          child: Form(
            key: authViewModel.registrationFormKey,
            child: Column(
              children: <Widget>[
                SizedBox(height: SizeConfig.heightMultiplier * 5),
                const LogoDisplay(),
                SizedBox(height: SizeConfig.heightMultiplier * 5),
                PrivateRegion(
                  child: CustomTextField(
                    label: 'Full Name',
                    hintText: 'Enter Full Name',
                    prefixIcon: Icons.person,
                    controller: authViewModel.nameController,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Full Name is required';
                      }
                      return null;
                    },
                  ),
                ),
                PrivateRegion(
                  child: CustomTextField(
                    label: 'Business Name',
                    hintText: 'Enter Business Name',
                    prefixIcon: Icons.store,
                    controller: authViewModel.shopNameController,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Business Name is required';
                      }
                      return null;
                    },
                  ),
                ),
                PrivateRegion(
                  child: CustomTextField(
                    label: 'Mobile Number',
                    hintText: 'Enter Mobile Number',
                    prefixIcon: Icons.phone,
                    controller: authViewModel.registrationMobileNoController,
                    textInputType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Mobile Number is required';
                      }
                      if (!isValidSAPhoneNumber(value)) {
                        return 'Enter a valid SA mobile number';
                      }
                      return null;
                    },
                  ),
                ),                SizedBox(height: SizeConfig.heightMultiplier * 1),
                ValueListenableBuilder<bool>(
                  valueListenable: authViewModel.isLoading,
                  builder: (context, isLoading, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: 'Register',
                          onTap: authViewModel.isLoading.value
                              ? () {}
                              : () {
                                  if (authViewModel
                                      .registrationFormKey.currentState!
                                      .validate()) {
                                    // Pass referrerUserId when registering
                                    authViewModel.registerUser(context,
                                        referrerUserId: referrerUserId);
                                  }
                                },
                          color: Colors.green,
                          fontSize: SizeConfig.textMultiplier * 2,
                          icon: Icons.person_add,
                        ),
                        if (isLoading)
                          const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)),
                      ],
                    );
                  },
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                if (FeatureFlags.enableAnonymousGate) ...[
                  CustomButton(
                    title: 'Explore',
                    onTap: () {
                      authViewModel.signInAnonymously(context);
                    },
                    color: Colors.blue,
                    icon: Icons.visibility,
                    fontSize: SizeConfig.textMultiplier * 2,
                  ),
                ],
                SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                CustomButton(
                  icon: FontAwesomeIcons.whatsapp,
                  title: 'Chat with support',
                  onTap: () => SupportUtil.sendWhatsAppMessage(
                      context, WhatsAppMessageType.support),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 1),
                OverflowBar(
                  alignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text('Already have an account?',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: SizeConfig.textMultiplier * 2,
                        )),
                    TextButton(
                      child: Text(
                        'LOGIN',
                        style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 2,
                            fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, '/loginPage');
                      },
                    ),
                  ],
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
