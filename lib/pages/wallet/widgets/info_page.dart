import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('How It Works & Fees 📖',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How It Works: 🚀',
              style: Theme.of(context)
                  .textTheme
                  .headline5
                  ?.copyWith(color: Colors.black87),
            ),
            SizedBox(height: 10),
            buildBulletPoint(
                'Account Setup: Add your banking details to start receiving payouts 💳.'),
            buildBulletPoint(
                'Viewing Balance: Check your current balance on the wallet page 📈.'),
            buildBulletPoint(
                'Requesting Payouts: Request payouts when your balance is positive 💰.'),
            buildBulletPoint(
                'Transaction History: Review your payout history in "History" 📜.'),
            SizedBox(height: 20),
            Text(
              'Fees: 💸',
              style: Theme.of(context)
                  .textTheme
                  .headline5
                  ?.copyWith(color: Colors.black87),
            ),
            SizedBox(height: 10),
            buildBulletPoint(
                'Service Fee: A fixed fee is applied to each payout to cover transaction costs 💵.'),
            buildBulletPoint(
                'No Hidden Charges: What you see is what you get, no surprise fees here 👀.'),
            buildBulletPoint(
                'Statements: Access detailed statements any time in "History" 📋.'),
            SizedBox(height: 20),
            Text(
              'Payouts: 🏦',
              style: Theme.of(context)
                  .textTheme
                  .headline5
                  ?.copyWith(color: Colors.black87),
            ),
            SizedBox(height: 10),
            buildBulletPoint(
                'Request Anytime: Payout requests are processed during business hours 🕒.'),
            buildBulletPoint(
                'Status Tracking: Stay updated with the status of your payout requests 🔍.'),
            buildBulletPoint(
                'Direct Deposits: Funds are directly deposited into your linked bank account 🏧.'),
            SizedBox(height: 20),
            Text(
              'Need Help? 🤔',
              style: Theme.of(context)
                  .textTheme
                  .headline5
                  ?.copyWith(color: Colors.black87),
            ),
            SizedBox(height: 10),
            InkWell(
              onTap: () => launchWhatsApp(context, '0648370009'),
              child: Text(
                'WhatsApp Us: 0648370009 📱',
                style: TextStyle(
                    color: Colors.blue, decoration: TextDecoration.underline),
              ),
            ),
            SizedBox(height: 5),
            InkWell(
              onTap: () => launchWhatsApp(context, '0825075622'),
              child: Text(
                'WhatsApp Us: 0825075622 📱',
                style: TextStyle(
                    color: Colors.blue, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBulletPoint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ',
                style:
                    TextStyle(fontSize: 30, height: 1, color: Colors.black54)),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ],
        ),
      );

  void launchWhatsApp(BuildContext context, String phone) async {
    final url = "https://wa.me/$phone";
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not launch WhatsApp'),
        ),
      );
    }
  }
}
