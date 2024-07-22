import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/contact/widgets/product_search_delegate.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductSelectionWidget<T extends TransactionViewModel>
    extends StatelessWidget {
  final T viewModel;

  ProductSelectionWidget({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius:
                BorderRadius.circular(SizeConfig.imageSizeMultiplier * 9),
          ),
          child: ListTile(
            leading:
                Icon(Icons.search, size: SizeConfig.imageSizeMultiplier * 6),
            title: Text(
              'Search Products',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
            ),
            onTap: () async {
              await showSearch<Product?>(
                context: context,
                delegate: ProductSearchDelegate(
                  viewModel: viewModel,
                ),
              );
            },
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        if (viewModel.selectedProducts.isNotEmpty)
          Column(
            children: [
              ...viewModel.paginatedSelectedProducts.map(
                (entry) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatStringToCamelCase(viewModel.products
                              .firstWhere((product) => product.id == entry.key)
                              .name!),
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 2),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.remove,
                            size: SizeConfig.imageSizeMultiplier * 6),
                        onPressed: () {
                          viewModel.updateProductQuantity(
                              context, entry.key, entry.value - 1);
                        },
                      ),
                      Text(
                        entry.value.toString(),
                        style:
                            TextStyle(fontSize: SizeConfig.textMultiplier * 2),
                      ),
                      IconButton(
                        icon: Icon(Icons.add,
                            size: SizeConfig.imageSizeMultiplier * 6),
                        onPressed: () {
                          viewModel.updateProductQuantity(
                              context, entry.key, entry.value + 1);
                        },
                      ),
                    ],
                  );
                },
              ),
              Container(
                height: SizeConfig.heightMultiplier * 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: viewModel.currentPage > 0
                            ? Colors.green
                            : Colors.grey,
                        size: SizeConfig.imageSizeMultiplier * 6,
                      ),
                      onPressed: viewModel.previousPage,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.arrow_forward,
                        color: (viewModel.currentPage + 1) *
                                    viewModel.itemsPerPage <
                                viewModel.selectedProducts.length
                            ? Colors.green
                            : Colors.grey,
                        size: SizeConfig.imageSizeMultiplier * 6,
                      ),
                      onPressed: viewModel.nextPage,
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          Column(children: [
            SizedBox(height: SizeConfig.heightMultiplier * 3),
            Center(
              child: Text(
                'No products added',
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 2,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ),
          ])
      ],
    );
  }
}
