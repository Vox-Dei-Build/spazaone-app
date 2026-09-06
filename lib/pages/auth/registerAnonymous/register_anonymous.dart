import 'package:flutter/material.dart';
import 'package:pasella/pages/auth/widgets/auth_shell.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/shared/widgets/vimeo_video_player.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/phone_util.dart';

class RegisterAnonymousPage extends StatefulWidget {
  const RegisterAnonymousPage({Key? key}) : super(key: key);
  static const id = '/registerAnonymousPage';

  @override
  State<RegisterAnonymousPage> createState() => _RegisterAnonymousPageState();
}

class _RegisterAnonymousPageState extends State<RegisterAnonymousPage> {
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
  Widget build(BuildContext context) => AuthShell(
        title: 'Create your account',
        subtitle: 'Add your details to keep your shop connected.',
        child: Form(
          key: authViewModel.registrationFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: 'Full name',
                hint: 'e.g. Thandi Mokoena',
                controller: authViewModel.nameController,
                validator: (value) => value == null || value.isEmpty
                    ? 'Full Name is required'
                    : null,
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Business name',
                hint: 'e.g. The Corner Shop',
                controller: authViewModel.shopNameController,
                validator: (value) => value == null || value.isEmpty
                    ? 'Shop Name is required'
                    : null,
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Mobile number',
                hint: '082 123 4567',
                controller: authViewModel.registrationMobileNoController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Mobile Number is required';
                  }
                  if (!isValidSAPhoneNumber(value)) return kSAOnlyPhoneMessage;
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ValueListenableBuilder<bool>(
                valueListenable: authViewModel.isLoading,
                builder: (context, isLoading, _) => AuthPrimaryButton(
                  label: 'Create account',
                  isLoading: isLoading,
                  onPressed: () {
                    if (authViewModel.registrationFormKey.currentState!
                        .validate()) {
                      authViewModel.registerAnonymousAccount(
                        context,
                        referrerUserId: referrerUserId,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VimeoVideoPage(
                      videoId: '935735574',
                      title: '',
                    ),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('How-to video'),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Already have an account?'),
                  TextButton(
                    onPressed: () => logout(context),
                    child: const Text('Log in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
