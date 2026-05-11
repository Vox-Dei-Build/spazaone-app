# pas-ux-05 — product upload flow simplification

## Current create-product flow (mapped)

Entry: `NewProductPage` (`lib/pages/stock/new_product_page/new_product_page.dart:21`)
Form: `ProductForm` (`lib/pages/stock/widgets/product_form.dart:9`)
Persistence: `ProductViewModel.saveProduct` (`lib/pages/stock/view_model/product_view_model.dart:89`)

Single-screen form, all fields rendered at once:

| Field         | Required | Source of truth |
|---------------|----------|------------------|
| Image         | no       | overlay tap, uploads to Firebase Storage before save |
| Product Name  | yes      | validator + `_validateInputs` |
| Cost          | yes      | validator + `_validateInputs` |
| Selling Price | yes      | validator + `_validateInputs` |
| Quantity      | yes      | validator + `_validateInputs` |
| Company       | no       | free-text |
| Description   | no       | free-text |
| Group         | passed in via `initialGroup` from `ProductGroupPage`; not rendered as a form field |
| Location      | not collected on create |

`ProductForm` is shared by create (`NewProductPage`) and edit (`ProductDetailsPage` `lib/pages/stock/product_details/product_details.dart:93`).

## Linked credit / sales behavior

Product creation does **not** force any accounting decision. Linked behavior surfaces downstream:

- `add_credit` reserves stock by reducing `product.quantity` at credit time (see `lib/pages/transactions/view_model/add_credit_view_model.dart`).
- `edit_transaction` returns reserved stock on credit deletion (`lib/pages/transactions/view_model/edit_transaction_view_model.dart:299`).

Implication: `quantity` is meaningful but does not need to be precise at creation. Merchants can enter `0` and adjust later; downstream credit/sales math still works (it just won't reserve negative stock until quantity > 0).

## Friction points (ranked)

1. **Form length on first contact.** Six visible inputs + image overlay before a merchant can save their first product. Mobile keyboard occludes half the form during entry.
2. **`Quantity*` framed as a precise number.** Merchants who haven't counted stock yet stall here. The UI does not signal that `0` is acceptable.
3. **Optional fields presented with same visual weight as required fields.** Company and Description are aspirational metadata for most merchants on first add; they pull attention from price/quantity decisions.
4. **No `group` selector inside the form.** Group is only inherited from the entry point. A merchant who lands on `NewProductPage` from a non-group surface has no way to pick one. *(Out of scope for this slice; flagged as follow-up.)*
5. **Image upload is in-flight before save.** Tapping the image overlay uploads immediately; if the merchant abandons the form, the upload is orphaned in storage. *(Out of scope; flagged.)*

## Required-now vs enrich-later

- **Required now:** name, cost, selling price, quantity (kept), image (kept optional).
- **Enrich later:** company, description, location.

## Slice implemented

`ProductForm` (`lib/pages/stock/widgets/product_form.dart`):

1. Wrapped `Company` and `Description` in an `ExpansionTile` titled **"More details (optional)"**, collapsed by default. Auto-expands when either controller already has text — preserves the edit-product experience without adding a new constructor param.
2. Changed `Quantity*` hint from `"Quantity"` to `"Enter 0 if unsure"` to legitimize the not-yet-counted case.

No schema change. No validator change. No save-flow change. Persistence path untouched.

## Verification

- `flutter analyze lib/pages/stock/widgets/product_form.dart` — 0 new issues; the 5 reported are pre-existing (`withOpacity` deprecations and the private-type-in-public-API info).
- Form continues to use the same `viewModel` controllers, so `hasUnsavedChanges`, FAB enable/disable, and save path behave identically.
- `ProductDetailsPage` (edit surface) — disclosure auto-opens when an existing product has a company or description, so legacy data stays visible.

## Next recommended slices

1. Add a `group` selector inside `ProductForm` (Autocomplete bound to `viewModel.productGroups`) so create works from any entry point.
2. Defer image upload until save: stage a local `XFile`, upload inside `saveProduct`, and roll back on failure. Removes orphaned uploads.
3. Consider relaxing `quantity` to optional with a default of `0` after a stock-math audit of `add_credit` / `edit_transaction`.
