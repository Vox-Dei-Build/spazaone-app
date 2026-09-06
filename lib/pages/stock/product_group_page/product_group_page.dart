import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/edit_product_group_dialog.dart';
import 'package:pasella/pages/stock/search/global_search.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'widgets/product_list.dart';

class ProductGroupPage extends StatelessWidget {
  final String name;
  final StockViewModel viewModel;

  const ProductGroupPage(
      {Key? key, required this.name, required this.viewModel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(
          bottom: 24,
          right: 4,
        ),
        child: SizedBox(
          height: 52,
          child: FloatingActionButton.extended(
            elevation: 0,
            backgroundColor: SpazaColors.action,
            foregroundColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) {
                    return NewProductPage(
                      group: name,
                    );
                  },
                ),
              );
            },
            icon: const Icon(
              Icons.add_outlined,
              color: Colors.white,
              size: 20, // Smaller icon
            ),
            label: const Text(
              'Add product',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
      appBar: CustomAppBar(
        title: name,
        // mainAxisSize.min keeps the Row from claiming the full
        // remaining width inside AppBar.actions, which was the cause
        // of the trailing-icon overflow on iPhone-class widths.
        // Icon size dropped from imageSizeMultiplier * 7 to * 5 to
        // match the rest of the codebase (template_detail_page,
        // view_promotion, product_details) and the AppBar's own
        // leading back-arrow scale.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.search,
                color: SpazaColors.ink,
                size: 22,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => GlobalSearchPage(
                      isGroupSearch: true,
                      groupName: name,
                      productsStream: viewModel.streamProducts(),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.edit,
                color: SpazaColors.ink,
                size: 22,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return EditProductGroupDialog(
                      viewModel: viewModel,
                      groupName: name,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      body: Container(
        child: SafeArea(
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ProductList(viewModel: viewModel, groupName: name),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
