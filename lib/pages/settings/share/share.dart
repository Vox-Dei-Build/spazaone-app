import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/settings/share/widget/referral_dashboard.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
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
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  int referralCount = 0;

  final String termsUrl =
      'https://docs.google.com/document/d/e/2PACX-1vRL93ZTWUYRkJtfVrAthmpwIWY7IuM3nWE0oj1jzmBj0mgvqi3l4AAAu6LGQs8u9-FPYrknfaXitKIj/pub';

  @override
  void initState() {
    super.initState();
    fetchUserData();
    // Load any previously generated referral link; otherwise share without a link.
    generateReferralLink();
  }

  void fetchUserData() async {
    try {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      final userSnapshot = await userRef.get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.data();
        if (mounted) {
          setState(() {
            referralCount = userData?['referralCount'] ?? 0;
          });
        }

        if (userData != null && userData['referralCount'] == null) {
          await userRef.update({'referralCount': 0});
        }
      }
    } catch (e) {
      print("Error fetching referral count: $e");
    }
  }

  String constructShareMessage() {
    final String expiryDate = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().add(const Duration(days: 30)));

    String message = 'Check out Pasella! 🚀\n'
        'Support your local spaza shop and stay connected. 🎉\n'
        'Sign up by $expiryDate.\n';

    if (referralLink != null) {
      String encodedLink = Uri.encodeFull(referralLink!);
      message += '\nHere\'s my link: $encodedLink';
    }

    return message;
  }

  void generateReferralLink() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final linkRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('referralLinks')
        .doc('myReferralLink');

    final snapshot = await linkRef.get();
    if (snapshot.exists && snapshot.data() != null) {
      final data = snapshot.data() as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        referralLink = data['link'];
      });
      return;
    }

    // No longer generating new referral links via Branch SDK.
    // If no existing link is found, share message will not include a link.
    if (!mounted) return;
    setState(() {
      referralLink = null;
    });
  }

  void shareToWhatsApp(String message) async {
    final whatsappUrl = "whatsapp://send?text=$message";
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
    SizeConfig().init(context);
    final double spacing = SizeConfig.blockSizeVertical * 2;
    final double textSize = SizeConfig.textMultiplier * 2;
    final double subtitleSize = SizeConfig.textMultiplier * 1.6;

    final String detailedMessage = constructShareMessage();

    return Scaffold(
      appBar: const CustomAppBar(title: 'Share Pasella'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(SizeConfig.blockSizeHorizontal * 3),
          child: Center(
            child: Column(
              children: [
                ReferralDashboard(referralCount: referralCount),
                SizedBox(height: spacing),
                Image.asset(
                  'assets/images/share.png',
                  width: SizeConfig.imageSizeMultiplier * 50,
                ),
                SizedBox(height: spacing),
                Text(
                  'Invite your friends and help grow the Pasella community!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: textSize, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: spacing),
                Text(
                  'Share your link and invite others to use Pasella with your shop. The more the merrier! ✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: subtitleSize),
                ),
                SizedBox(height: spacing),
                if (referralLink != null)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: referralLink ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Referral link copied to clipboard!',
                              style: TextStyle(fontSize: textSize))));
                    },
                    child: Text(
                      referralLink ?? '',
                      style: TextStyle(
                          fontSize: textSize,
                          color: Colors.blue,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                SizedBox(height: spacing),
                // Always allow sharing; message includes link only if available.
                ElevatedButton.icon(
                  icon: Icon(
                    Icons.share,
                    size: textSize,
                  ),
                  label: Text('Share', style: TextStyle(fontSize: textSize)),
                  onPressed: () => Share.share(detailedMessage),
                ),
                ElevatedButton.icon(
                  icon: Icon(
                    FontAwesomeIcons.whatsapp,
                    size: textSize,
                  ),
                  label: Text('WhatsApp', style: TextStyle(fontSize: textSize)),
                  onPressed: () => shareToWhatsApp(detailedMessage),
                ),
                Padding(
                  padding: EdgeInsets.all(SizeConfig.blockSizeVertical),
                  child: InkWell(
                    onTap: () => _launchURL(termsUrl),
                    child: Text(
                      "Terms and Conditions",
                      style: TextStyle(
                          fontSize: textSize,
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
    );
  }
}
