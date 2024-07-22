import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';

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
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(0.0),
            visualDensity: const VisualDensity(horizontal: -2),
            leading: _buildLeadingIcon(context),
            title: _buildTitle(),
            subtitle: _buildSubtitle(),
          ),
          const Divider(
            color: kHighLightColor,
            height: 5,
          ),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(BuildContext parentContext) {
    return Stack(
      children: [
        InkWell(
          onTap: () {
            showDialog(
              context: parentContext,
              builder: (BuildContext context) {
                return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                        padding:
                            EdgeInsets.all(SizeConfig.imageSizeMultiplier * 4),
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.8,
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              profileImageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: profileImageUrl!,
                                      placeholder: (context, url) =>
                                          CircularProgressIndicator(),
                                      errorWidget: (context, url, error) =>
                                          Icon(Icons.error),
                                    )
                                  : CircleAvatar(
                                      backgroundColor:
                                          Color(kTertiaryColor.value),
                                      radius: SizeConfig.heightMultiplier * 2.5,
                                      child: Text(
                                        name.isNotEmpty ? name[0] : '',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize:
                                              SizeConfig.textMultiplier * 2.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text('Close'),
                              )
                            ],
                          ),
                        )));
              },
            );
          },
          child: CircleAvatar(
            radius: SizeConfig.heightMultiplier * 2.5, // Fixed size
            backgroundImage: profileImageUrl != null
                ? CachedNetworkImageProvider(profileImageUrl!)
                : null,
            child: profileImageUrl == null
                ? Text(
                    name.isNotEmpty ? name[0] : '',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: SizeConfig.textMultiplier * 2,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : null,
          ),
        ),
        if (number == null || number!.isEmpty)
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.phone_disabled,
              color: Colors.red,
              size: SizeConfig.imageSizeMultiplier * 3,
            ),
          )
        else
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.phone_enabled,
              color: Colors.green,
              size: SizeConfig.imageSizeMultiplier * 3,
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Icon(
            isNPA == true ? Icons.report : Icons.verified_user,
            color: isNPA == true ? Colors.red : Colors.green,
            size: SizeConfig.imageSizeMultiplier * 3,
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Text(
            CurrencyUtil.format(balance),
            style: TextStyle(
              color: balance >= 0 ? kPrimaryColor : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 1.8,
            ),
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
                fontSize: SizeConfig.textMultiplier * 1.6,
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
