import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/otp_code_dialog.dart';

class _FakeAuth implements FirebaseAuth {
  final requests = <Map<Symbol, dynamic>>[];
  int signInCalls = 0;
  User? _user;
  Completer<UserCredential>? pendingSignIn;

  void sendCode() =>
      (requests.last[#codeSent] as PhoneCodeSent)('test-verification', null);

  Future<void> autoVerify() async {
    // The SDK callback is void-typed but our production callback is async;
    // keep its returned future so tests can await background account setup.
    final dynamic callback = requests.last[#verificationCompleted];
    await callback(PhoneAuthProvider.credential(
      verificationId: 'test-verification',
      smsCode: '123456',
    ));
  }

  @override
  User? get currentUser => _user;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signInCalls++;
    if (pendingSignIn != null) return pendingSignIn!.future;
    _user = _FakeUser();
    return _FakeUserCredential(_user!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #verifyPhoneNumber) {
      requests.add(invocation.namedArguments);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeUser implements User {
  _FakeUser([this.uid = 'synthetic-merchant']);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserCredential implements UserCredential {
  _FakeUserCredential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirestore implements FirebaseFirestore {
  _FakeFirestore({this.pendingLookup, this.registered = true});

  final Completer<QuerySnapshot<Map<String, dynamic>>>? pendingLookup;
  final bool registered;
  final writes = <String, Map<String, dynamic>>{};
  final readSources = <Source?>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _FakeUsers(this, path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK interface fakes control completion order without a Firebase app,
// network access, or customer records.
// ignore: subtype_of_sealed_class
class _FakeUsers implements CollectionReference<Map<String, dynamic>> {
  _FakeUsers(this.firestore, this.path);
  final _FakeFirestore firestore;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDoc(firestore, '${this.path}/$path');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    // Keep the existing authoritative lookup: cached emptiness must never be
    // mistaken for a new customer during the lifecycle fix.
    firestore.readSources.add(options?.source);
    return firestore.pendingLookup?.future ??
        Future.value(_RegisteredSnapshot(registered: firestore.registered));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where || invocation.memberName == #limit) {
      return this;
    }
    return super.noSuchMethod(invocation);
  }
}

class _RegisteredSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _RegisteredSnapshot({this.registered = true});
  final bool registered;
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs =>
      registered ? [_UserDoc()] : [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _UserDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeDoc implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this.firestore, this.path);
  final _FakeFirestore firestore;
  @override
  final String path;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    firestore.writes[path] = data;
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeUsers(firestore, '${this.path}/$path');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthHost extends StatefulWidget {
  const _AuthHost({required this.model, required this.onStarted});
  final AuthViewModel model;
  final void Function(Future<void>) onStarted;

  @override
  State<_AuthHost> createState() => _AuthHostState();
}

class _AuthHostState extends State<_AuthHost> {
  @override
  void dispose() {
    widget.model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextButton(
          onPressed: () => widget.onStarted(
            widget.model.lookupAndRoute(this.context, '0821234567',
                referrerUserId: 'synthetic-referrer'),
          ),
          child: const Text('Continue'),
        ),
      );
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => 'wifi',
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  Future<({GlobalKey<NavigatorState> navigator, Future<void> flow})> startFlow(
    WidgetTester tester,
    _FakeAuth auth, {
    _FakeFirestore? firestore,
  }) async {
    final navigator = GlobalKey<NavigatorState>();
    final database = firestore ?? _FakeFirestore();
    late Future<void> flow;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      routes: {
        '/dashboard': (_) => const Scaffold(body: Text('Signed in')),
        '/finishProfilePage': (_) =>
            const Scaffold(body: Text('Finish profile')),
      },
      home: _AuthHost(
        model: AuthViewModel(auth: auth, firestore: database),
        onStarted: (value) => flow = value,
      ),
    ));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(database.readSources, isNotEmpty);
    expect(database.readSources, everyElement(Source.server));
    return (navigator: navigator, flow: flow);
  }

  Future<void> leaveFlow(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigator,
  ) async {
    unawaited(navigator.currentState!.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another screen')),
      ),
      (_) => false,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('detached StatefulElement cannot launch the shared OTP dialog',
      (tester) async {
    late BuildContext staleContext;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, _) {
        staleContext = context;
        return const Scaffold();
      }),
    ));
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    expect(staleContext.mounted, isFalse);
    expect(
      await showOtpCodeDialog(
        staleContext,
        maskedNumber: '+27•••567',
        onVerify: (_) async => fail('Detached prompt must not verify'),
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(OtpCodeDialog), findsNothing);
  });

  testWidgets(
      'late codeSent after leaving does not open an OTP or notify disposed model',
      (tester) async {
    final auth = _FakeAuth();
    final run = await startFlow(tester, auth);
    expect(auth.requests, hasLength(1));
    await leaveFlow(tester, run.navigator);
    await run.flow;

    auth.sendCode();
    await tester.pumpAndSettle();
    expect(find.text('Another screen'), findsOneWidget);
    expect(find.byType(OtpCodeDialog), findsNothing);
    expect(auth.signInCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late auto-verification after leaving cannot sign in or navigate',
      (tester) async {
    final auth = _FakeAuth();
    final run = await startFlow(tester, auth);
    await leaveFlow(tester, run.navigator);
    await run.flow;

    auth.autoVerify();
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 0);
    expect(find.text('Another screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lookup completing after leaving never requests an SMS',
      (tester) async {
    final auth = _FakeAuth();
    final lookup = Completer<QuerySnapshot<Map<String, dynamic>>>();
    final run = await startFlow(
      tester,
      auth,
      firestore: _FakeFirestore(pendingLookup: lookup),
    );
    await leaveFlow(tester, run.navigator);
    lookup.complete(_RegisteredSnapshot());
    await tester.pumpAndSettle();
    await run.flow;
    expect(auth.requests, isEmpty);
    expect(find.text('Another screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active manual OTP still signs in and routes to dashboard',
      (tester) async {
    final auth = _FakeAuth();
    final run = await startFlow(tester, auth);
    auth.sendCode();
    await tester.pumpAndSettle();
    expect(find.byType(OtpCodeDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    await run.flow;
    expect(auth.signInCalls, 1);
    expect(find.text('Signed in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final promptVisible in [false, true]) {
    testWidgets(
        'active auto-verification routes once (prompt visible: $promptVisible)',
        (tester) async {
      final auth = _FakeAuth();
      final run = await startFlow(tester, auth);
      if (promptVisible) {
        auth.sendCode();
        await tester.pumpAndSettle();
      }
      auth.autoVerify();
      await tester.pumpAndSettle();
      await run.flow;
      expect(auth.signInCalls, 1);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.byType(OtpCodeDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelled OTP ignores late automatic verification',
      (tester) async {
    final auth = _FakeAuth();
    final run = await startFlow(tester, auth);
    auth.sendCode();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await run.flow;
    auth.autoVerify();
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 0);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final automatic in [false, true]) {
    testWidgets(
        'accepted registration finishes after disposal (auto: $automatic)',
        (tester) async {
      final signIn = Completer<UserCredential>();
      final auth = _FakeAuth()..pendingSignIn = signIn;
      final firestore = _FakeFirestore(registered: false);
      final run = await startFlow(tester, auth, firestore: firestore);
      Future<void>? autoCompletion;
      if (automatic) {
        autoCompletion = auth.autoVerify();
      } else {
        auth.sendCode();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '123456');
        await tester.tap(find.text('Verify'));
      }
      await tester.pump();
      expect(auth.signInCalls, 1);
      await leaveFlow(tester, run.navigator);

      // currentUser stays null: persist using the accepted credential's UID.
      signIn.complete(_FakeUserCredential(_FakeUser('accepted-merchant')));
      await tester.pumpAndSettle();
      await autoCompletion;
      await run.flow;
      expect(firestore.writes.keys, contains('users/accepted-merchant'));
      expect(
          firestore.writes['users/accepted-merchant'],
          containsPair(
            'mobileNumberNormalized',
            '0821234567',
          ));
      expect(
          firestore.writes['users/accepted-merchant'],
          containsPair(
            'referrerUserId',
            'synthetic-referrer',
          ));
      expect(firestore.writes['users/accepted-merchant/wallet/current'],
          containsPair('virtualBalance', 15.0));
      expect(find.text('Another screen'), findsOneWidget);
      expect(find.text('Finish profile'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('active registration persists before routing to finish profile',
      (tester) async {
    final auth = _FakeAuth();
    final firestore = _FakeFirestore(registered: false);
    final run = await startFlow(tester, auth, firestore: firestore);
    auth.sendCode();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    await run.flow;
    expect(
        firestore.writes.keys,
        containsAll([
          'users/synthetic-merchant',
          'users/synthetic-merchant/wallet/current',
        ]));
    expect(find.text('Finish profile'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
