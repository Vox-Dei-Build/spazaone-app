import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
      padding: const EdgeInsets.all(8),
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
          margin: const EdgeInsets.symmetric(vertical: 8),
          height: SizeConfig.heightMultiplier * 18,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(SpazaRadius.surface),
            border: Border.all(color: SpazaColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (productCount != null)
                Text(
                  '$productCount',
                  style: const TextStyle(
                    fontSize: 18,
                    color: SpazaColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
