import 'package:flutter/material.dart';
import 'package:pasella/pages/stock/search/widgets/global_search_bar.dart';
import 'package:pasella/pages/stock/search/widgets/search_product_list.dart';
import 'package:pasella/pages/stock/view_model/global_search_view_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

class GlobalSearchPage extends StatelessWidget {
  final bool isGroupSearch;
  final String? groupName;
  final Stream<List<Product>>? productsStream;

  const GlobalSearchPage({
    Key? key,
    this.isGroupSearch = false,
    this.groupName,
    this.productsStream,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GlobalSearchViewModel(productsStream: productsStream),
      builder: (context, child) {
        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: CustomAppBar(
            title: isGroupSearch ? 'Search in $groupName' : 'Product search',
          ),
          body: SafeArea(
            child: Column(
              children: [
                GlobalSearchBar(
                  onSearch: (query) {
                    Provider.of<GlobalSearchViewModel>(context, listen: false)
                        .updateSearchQuery(query,
                            isGroupSearch: isGroupSearch, groupName: groupName);
                  },
                ),
                Expanded(
                  child: Consumer<GlobalSearchViewModel>(
                    builder: (context, viewModel, child) {
                      return SearchProductList(
                          products: viewModel.searchResults);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
