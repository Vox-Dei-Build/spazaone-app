import 'package:flutter/foundation.dart';
import 'package:pasella/models/sales/sales_model.dart';

enum SaleEditOutcome { updated, deleted }

/// Explicit navigation result returned by the sale editor.
///
/// An update carries the newly persisted sale so the detail page can refresh
/// in place. A deletion carries no sale because the detail route must close.
@immutable
class SaleEditResult {
  const SaleEditResult.updated(Sale updatedSale)
      : outcome = SaleEditOutcome.updated,
        sale = updatedSale;

  const SaleEditResult.deleted()
      : outcome = SaleEditOutcome.deleted,
        sale = null;

  final SaleEditOutcome outcome;
  final Sale? sale;
}
