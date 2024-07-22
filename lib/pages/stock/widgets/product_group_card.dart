import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/stock/product_group_page/product_group_page.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

class ProductGroupCard extends StatelessWidget {
  final StockViewModel viewModel;
  final String name;
  final int? productCount;

  const ProductGroupCard({
    Key? key,
    required this.viewModel,
    required this.name,
    this.productCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Padding(
      padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 1.5),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                return ProductGroupPage(name: name, viewModel: viewModel);
              },
            ),
          );
        },
        child: Container(
          margin:
              EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
          height: SizeConfig.heightMultiplier * 18,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                offset: Offset(0, SizeConfig.heightMultiplier * 0.6),
                blurRadius: 6,
                color: Color(0xff000000).withOpacity(0.16),
              ),
            ],
          ),
          padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (productCount != null)
                Text(
                  '$productCount',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
