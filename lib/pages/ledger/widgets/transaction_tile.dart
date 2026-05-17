import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/shared/widgets/payment_status_pill.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/widgets/private_region.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.color,
    required this.name,
    required this.amount,
    required this.remarks,
    required this.status,
    required this.type,
    required this.date,
    required this.selectedCustomerId,
    required this.balance,
    this.isNPA,
    this.number,
    this.profileImageUrl, // Add profileImageUrl
    required this.unreadCount,
  });

  final int color;
  final String name;
  final double amount;
  final String remarks;
  final String type;
  final String status;
  final String date;
  final String selectedCustomerId;
  final double balance;
  final bool? isNPA;
  final String? number;
  final String? profileImageUrl; // Add profileImageUrl
  final int? unreadCount;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CustomerManagementPage(
              customerName: name,
              customerId: selectedCustomerId,
              mobileNumber: number,
            ),
          ),
        );
      },
      // Most privacy-sensitive list in the app: customer name + outstanding
      // balance on every row. Mask the rendered Column so replays show
      // shapes but no PII; GestureDetector stays outside so taps record.
      child: PrivateRegion(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(0.0),
              visualDensity: const VisualDensity(horizontal: -2),
              minLeadingWidth: SizeConfig.imageSizeMultiplier * 12,
              horizontalTitleGap: SizeConfig.imageSizeMultiplier * 2,
              leading: SizedBox(
                width: SizeConfig.imageSizeMultiplier * 12,
                height: SizeConfig.imageSizeMultiplier * 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: profilePicture(
                    context,
                    name,
                    profileImageUrl,
                    number,
                    isNPA,
                    balance: balance,
                    showNPAIndicator: false,
                    radius: SizeConfig.heightMultiplier * 2.6,
                  ),
                ),
              ),
              title: _buildTitle(),
              subtitle: _buildSubtitle(),
            ),
            const Divider(
              color: kHighLightColor,
              height: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    var unreadMessageCount = unreadCount ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Wrap the name + badge in Expanded so it doesn't overflow the balance
          Expanded(
            child: Row(
              children: [
                // Wrap name in Flexible to ellipsize correctly
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: SizeConfig.textMultiplier * 1.8,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (unreadMessageCount > 0)
                  Padding(
                    padding: EdgeInsets.only(
                        left: SizeConfig.imageSizeMultiplier * 1),
                    child: CircleAvatar(
                      radius: SizeConfig.imageSizeMultiplier * 2,
                      backgroundColor: Colors.green,
                      child: Text(
                        unreadMessageCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: SizeConfig.textMultiplier * 1.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                CurrencyUtil.format(balance),
                style: TextStyle(
                  color: balance >= 0 ? kPrimaryColor : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: SizeConfig.textMultiplier * 1.8,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.4),
              PaymentStatusPill(balance: balance, dense: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitle() {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: status == 'PAID' ? kPrimaryColor : Colors.red,
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 1.5,
              ),
              children: [
                TextSpan(text: CurrencyUtil.format(amount)),
                TextSpan(
                  text: type.isNotEmpty ? ' $type added on ' : ' ',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: date,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: SizeConfig.heightMultiplier * 2),
        Text(
          remarks,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: SizeConfig.textMultiplier * 1.4,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
