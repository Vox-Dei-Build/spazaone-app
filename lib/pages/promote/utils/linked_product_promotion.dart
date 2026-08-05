import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:provider/provider.dart';

typedef LinkedProductPromotionLauncher = Future<void> Function(
  BuildContext context,
  LinkedProductRef product,
);

LinkedProductRef promotionProductRef(Product product, String productId) {
  return LinkedProductRef(
    id: productId,
    name: product.name ?? 'Product',
    sellingPrice: product.sellingPrice,
    imageUrl: product.image,
    whatsappListed: product.whatsappListed,
  );
}

Future<void> launchLinkedProductPromotion(
  BuildContext context,
  LinkedProductRef product,
) {
  return RunPromotionLauncher.launch(
    context,
    viewModel: context.read<PromotionsViewModel>(),
    initialProduct: product,
  );
}
