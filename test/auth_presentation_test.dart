import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/auth/widgets/auth_shell.dart';
import 'package:pasella/pages/auth/widgets/login_ui.dart';
import 'package:pasella/pages/auth/widgets/otp_code_dialog.dart';
import 'package:pasella/utils/phone_util.dart';

Widget _app(Widget home, {double textScale = 1, double keyboardHeight = 0}) =>
    MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: child!,
      ),
      home: home,
    );

void _narrowScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('phone entry validates and accepts the SA international format',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var submissions = 0;
    await tester.pumpWidget(_app(PhoneAuthScreen(
      controller: controller,
      formKey: GlobalKey<FormState>(),
      onContinue: () => submissions++,
    )));
    await tester.tap(find.text('Send sign-in code'));
    await tester.pump();
    expect(find.text('Enter your mobile number'), findsOneWidget);
    expect(submissions, 0);

    await tester.enterText(find.byType(TextFormField), '+44 7700 900123');
    await tester.tap(find.text('Send sign-in code'));
    await tester.pump();
    expect(find.text(kSAOnlyPhoneMessage), findsOneWidget);
    expect(submissions, 0);

    await tester.enterText(find.byType(TextFormField), '+27 82 123 4567');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submissions, 1);
    expect(find.text(kSAOnlyPhoneMessage), findsNothing);
  });

  testWidgets('phone action is reachable with keyboard and 2x text at 320px',
      (tester) async {
    _narrowScreen(tester);
    final controller = TextEditingController(text: '082 123 4567');
    addTearDown(controller.dispose);
    var submissions = 0;
    await tester.pumpWidget(_app(
      PhoneAuthScreen(
        controller: controller,
        formKey: GlobalKey<FormState>(),
        onContinue: () => submissions++,
      ),
      textScale: 2,
      keyboardHeight: 260,
    ));
    await tester.ensureVisible(find.text('Send sign-in code'));
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('Send sign-in code')).dy,
        lessThanOrEqualTo(380));
    await tester.tap(find.text('Send sign-in code'));
    await tester.pump();
    expect(submissions, 1);
  });

  testWidgets('short landscape keeps the phone action reachable at 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '082 123 4567');
    addTearDown(controller.dispose);
    var submissions = 0;
    await tester.pumpWidget(_app(
      PhoneAuthScreen(
        controller: controller,
        formKey: GlobalKey<FormState>(),
        onContinue: () => submissions++,
      ),
      textScale: 2,
      keyboardHeight: 140,
    ));

    await tester.ensureVisible(find.text('Send sign-in code'));
    await tester.tap(find.text('Send sign-in code'));
    await tester.pump();
    expect(submissions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external phone label remains attached to the accessible field',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController(text: '082 123 4567');
    try {
      await tester.pumpWidget(_app(PhoneAuthScreen(
        controller: controller,
        formKey: GlobalKey<FormState>(),
        onContinue: () {},
      )));
      final phoneSemantics = tester.getSemantics(find.byType(TextFormField));
      expect(phoneSemantics.label, contains('Mobile number'));
      expect(phoneSemantics.value, '082 123 4567');
    } finally {
      semantics.dispose();
      controller.dispose();
    }
  });

  testWidgets('loading disables the field and both login actions',
      (tester) async {
    final controller = TextEditingController(text: '0821234567');
    addTearDown(controller.dispose);
    var submissions = 0;
    var registrations = 0;
    await tester.pumpWidget(_app(PhoneAuthScreen(
      controller: controller,
      formKey: GlobalKey<FormState>(),
      isReturningUser: true,
      isLoading: true,
      onContinue: () => submissions++,
      onCreateAccount: () => registrations++,
    )));
    expect(find.text('Sending code…'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse);
    await tester.ensureVisible(find.text('Sending code…'));
    await tester.tap(find.text('Sending code…'));
    await tester.ensureVisible(find.text('Create a business account'));
    await tester.tap(find.text('Create a business account'));
    expect(submissions, 0);
    expect(registrations, 0);
  });

  testWidgets('login uses a flat business layout without decorative emblem',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(PhoneAuthScreen(
      controller: controller,
      formKey: GlobalKey<FormState>(),
      isReturningUser: true,
      onContinue: () {},
      onCreateAccount: () {},
    )));
    expect(find.byKey(const ValueKey('auth-shop-emblem')), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Send sign-in code'), findsOneWidget);
    expect(find.text('Create a business account'), findsOneWidget);
    final panel = tester.widget<Container>(
      find.byKey(const ValueKey('auth-form-panel')),
    );
    expect(panel.decoration, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile fields retain required business-name validation',
      (tester) async {
    _narrowScreen(tester);
    final name = TextEditingController();
    final shop = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(shop.dispose);
    final formKey = GlobalKey<FormState>();
    var saves = 0;
    void save() {
      if (formKey.currentState!.validate()) saves++;
    }

    await tester.pumpWidget(_app(
      AuthShell(
        title: 'Set up your shop',
        subtitle: 'Add your name and the business name customers will see.',
        child: Form(
          key: formKey,
          child: Column(
            children: [
              ProfileDetailsFields(
                nameController: name,
                shopController: shop,
                onSubmitted: save,
                limitShopName: true,
              ),
              const SizedBox(height: 24),
              AuthPrimaryButton(label: 'Continue', onPressed: save),
            ],
          ),
        ),
      ),
      textScale: 2,
      keyboardHeight: 260,
    ));
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Enter your business name'), findsOneWidget);
    expect(saves, 0);
    await tester.enterText(find.byType(TextFormField).first, 'Thandi Mokoena');
    await tester.enterText(find.byType(TextFormField).last, 'A');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Business name is too short'), findsOneWidget);
    expect(saves, 0);
    await tester.enterText(find.byType(TextFormField).last, 'The Corner Shop');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'OTP retry and cancel remain reachable with keyboard and large text',
      (tester) async {
    _narrowScreen(tester);
    bool? result;
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showOtpCodeDialog(
                context,
                maskedNumber: '+27***567',
                onVerify: (_) async => false,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
      textScale: 2,
      keyboardHeight: 260,
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.ensureVisible(find.text('Verify'));
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text("That code didn't work. Check the SMS and try again."),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
