import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pasella/pages/settings/share/widget/referral_dashboard.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:pasella/shared/widgets/vimeo_video_player.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SharePage extends StatefulWidget {
  const SharePage({Key? key}) : super(key: key);

  static const id = '/sharePage';

  @override
  _SharePageState createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  String? referralLink;
  BranchUniversalObject? buo;
  BranchLinkProperties lp = BranchLinkProperties();
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  int referralCount = 0;
  double virtualBalance = 0.0;
  bool balanceLoading = false;
  final String termsUrl =
      'https://docs.google.com/document/d/e/2PACX-1vRL93ZTWUYRkJtfVrAthmpwIWY7IuM3nWE0oj1jzmBj0mgvqi3l4AAAu6LGQs8u9-FPYrknfaXitKIj/pub';

  @override
  void initState() {
    super.initState();
    fetchUserData();
    initializeDeepLinkData().then((value) => generateReferralLink());
  }

  @override
  void dispose() {
    super.dispose();
  }

  void fetchUserData() async {
    setState(() {
      balanceLoading = true;
    });

    try {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      final walletRef = userRef.collection('wallet').doc('current');

      final userSnapshot = await userRef.get();
      final walletSnapshot = await walletRef.get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.data();
        final walletData = walletSnapshot.data();

        setState(() {
          // Virtual Balance comes from subcollection
          if (walletData != null && walletData.containsKey('virtualBalance')) {
            final balance = walletData['virtualBalance'];
            virtualBalance =
                balance is int ? balance.toDouble() : (balance ?? 0.0);
          } else {
            virtualBalance = 0.0;
          }

          referralCount = userData?['referralCount'] ?? 0;
        });

        // Ensure referralCount is initialized
        if (userData != null && userData['referralCount'] == null) {
          await userRef.update({'referralCount': 0});
        }
      }
    } catch (e) {
      print("Error fetching balance info: $e");
    } finally {
      setState(() {
        balanceLoading = false;
      });
    }
  }

  //To Setup Data For Generation Of Deep Link
  Future<void> initializeDeepLinkData() async {
    // Directly await the asynchronous calls
    String shopName = await fetchShopNameForUser(userId) ?? '';
    String mobileNumber = await fetchNumberForUser(userId) ?? '';
    String name = await fetchNameForUser(userId) ?? '';

    // Construct title after name is fetched
    String title = name != ''
        ? "$name Invites You to Join Pasella – Claim Your R50 Credit!"
        : "Join Pasella – Claim Your R50 Credit!";

    buo = BranchUniversalObject(
      canonicalIdentifier: "flutter/branch",
      title: title,
      contentDescription: constructShareMessage(),
      imageUrl:
          'https://res.cloudinary.com/duz53ygxp/image/upload/v1699541340/Pasella_512x512_dark.png',
      contentMetadata: BranchContentMetaData()
        ..addCustomMetadata('userId', userId)
        ..addCustomMetadata('shopName', shopName)
        ..addCustomMetadata('mobileNumber', mobileNumber),
    );

    FlutterBranchSdk.registerView(buo: buo!);

    lp = BranchLinkProperties(
      channel: 'social',
      feature: 'referral',
      campaign: 'boost_referral_program',
      stage: 'level_1',
      alias: shopName,
      tags: [
        'pasella',
        'referral',
        shopName,
        name,
      ],
    );
  }

  String constructShareMessage() {
    final String expiryDate = DateFormat('yyyy-MM-dd').format(DateTime.now()
            .add(const Duration(days: 30)) // Adding 30 days as the expiry date
        );

    String message = 'Join me on Pasella and get R50 credit! 🌟\n'
        'Successfully onboard 5 customers on the ledger on our app to qualify for additional rewards.\n'
        'Let’s thrive together! Sign up by $expiryDate.\n'
        'Exclusive to invited members only! 🚀';

    // Append referral link if it exists
    if (referralLink != null) {
      String encodedLink = Uri.encodeFull(referralLink!);
      message += '\nHere\'s my referral link: $encodedLink';
    }

    return message;
  }

  void generateReferralLink() async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    final User? user = auth.currentUser;

    if (user == null) {
      print("User is not logged in.");
      return;
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final DocumentReference linkRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('referralLinks')
        .doc('myReferralLink'); // Static ID for the referral link document

    DocumentSnapshot snapshot = await linkRef.get();
    if (snapshot.exists && snapshot.data() != null) {
      final data = snapshot.data() as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          referralLink = data['link'];
        });
      }
      return;
    }

    // Generate the link if it does not exist
    BranchResponse response =
        await FlutterBranchSdk.getShortUrl(buo: buo!, linkProperties: lp);
    if (response.success) {
      if (mounted) {
        setState(() {
          referralLink = response.result;
        });
      }
      await linkRef.set(
          {'link': referralLink, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      print('Failed to generate referral link: ${response.errorMessage}');
    }
  }

  void showShareOptions(BuildContext context, String text) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share using other apps'),
                onTap: () {
                  Share.share(text);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(FontAwesomeIcons.whatsapp),
                title: const Text('Share on WhatsApp'),
                onTap: () {
                  shareToWhatsApp(text);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void shareToWhatsApp(String message) async {
    var whatsappUrl = "whatsapp://send?text=$message";
    if (await canLaunch(whatsappUrl)) {
      await launch(whatsappUrl);
    } else {
      throw 'Could not launch $whatsappUrl';
    }
  }

  void _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String detailedMessage = constructShareMessage();

    return Scaffold(
      appBar: const CustomAppBar(title: 'Share and Earn'),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  balanceLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ReferralDashboard(
                          referralCount: referralCount,
                          rewardsEarned: virtualBalance),
                  Image.asset(
                    'assets/images/share.png',
                    width: 200,
                  ),
                  const SizedBox(height: 10.0),
                  const Text(
                    'Invite your friends and earn rewards!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Share your referral link and get R100 cash for each friend who signs up, and your friend will also get R50. Help us grow! Ensure each friend onboards at least 5 customers and completes transactions worth R1000 through our app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  referralLink == null
                      ? const Text(
                          "Generating your unique referral link... Please wait...",
                          style: TextStyle(color: Colors.black))
                      : InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: referralLink ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Referral link copied to clipboard!')));
                          },
                          child: Text(
                            referralLink ?? '',
                            style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline),
                          ),
                        ),
                  const SizedBox(height: 20),
                  referralLink != null
                      ? ElevatedButton.icon(
                          icon: const Icon(Icons.share),
                          label: const Text('Share Link'),
                          onPressed: () => Share.share(detailedMessage),
                        )
                      : Container(),
                  referralLink != null
                      ? ElevatedButton.icon(
                          icon: const Icon(FontAwesomeIcons.whatsapp),
                          label: const Text('WhatsApp'),
                          onPressed: () => shareToWhatsApp(detailedMessage),
                        )
                      : Container(),
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.video_library,
                      color: Colors.white,
                    ),
                    label: const Text('Watch Referral Tutorial',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => VimeoVideoPage(
                          videoId: '935773465',
                          title: 'How the referral works'),
                    )),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.green, // Optional: Customize button color
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: InkWell(
                      onTap: () => _launchURL(termsUrl),
                      child: const Text(
                        "Terms and Conditions",
                        style: TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
