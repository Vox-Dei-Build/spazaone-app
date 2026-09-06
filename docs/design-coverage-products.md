# Products and recorded-sale detail design coverage

This pass applies the selected **Clean and approachable** direction to the product workspace and its reachable secondary screens. It uses the shared charcoal headings, green actions, neutral canvas, white rounded surfaces, bundled font and theme controls. Stock calculations, product identities, availability gates, promotions, invoice storage and supplier pricing remain in their existing owners.

| Screen family | Coverage |
| --- | --- |
| Products catalogue | Existing approachable rows and stock filters retained. Supplier-fulfilled and unset stock remain distinct from local out-of-stock items. |
| Add/edit product | Shared canvas and gutters, sentence-case labels, fixed spacing/type scale, rounded image area, consistent destructive action and confirmation. Existing validators, unsaved changes, listing/image requirements and product save flow retained. |
| Product search | Matching white cards, shared colours/type; large text uses growing rows instead of fixed-height grid cards. Stable product IDs and navigation retained. |
| Stock report | Softer summary, quieter weights and rounded attention rows. Summary values stack with large text; low-stock labels wrap. Existing calculation inputs and low-stock selection retained. |
| Supplier catalogue / saved products / listing sheet | Shared surface, border, action and secondary text colours; softer card, sheet and input radii. Delivery/availability warnings retain distinct meaning. Existing search, paging, saved state, variant/quote checks and create-listing callbacks remain. |
| Supplier listing details | Matching theme colours, type and radii. Existing promotion and markup behavior retained. |
| Recorded-sale details | A read-only presentation groups amount, date/type, remarks, products and private invoices into calm cards. Product lookup remains batched in the live page. Edit navigation and invoice preview loading remain owned by the live page. |
| Edit sale / stock amount / invoice attachments | Edit action uses the shared green, field border follows theme, labels use sentence case, attachment previews have consistent rounding. Stock amount semantics and validation remain unchanged. |
| Product groups and compatibility screens | Group cards/dialogs/buttons and legacy commerce-order surfaces receive theme/token cleanup. No new navigation entry or capability is enabled. |

## Additional preview screens

`tool/product_design_previews.dart` exports `Map<String, WidgetBuilder> productDesignPreviews()` for the All screens gallery:

- Add product and Edit product use the real `ProductForm` with a local provider and injected shop-name loader.
- Supplier catalogue uses the real `SupplierCatalogPage` with synthetic catalogue/saved data; creating a listing is blocked by the local callback.
- Product search uses the real search field and `SearchProductList`; selecting a local result opens that product's fixture values.
- Stock report uses the real `ProductReportsTab` with a data-only model.
- Sale details uses the real `SaleDetailsContent` with an in-memory product lookup.

The fixtures do not instantiate Firebase, upload images, call supplier APIs or save live data. Preview form buttons validate local fields and explicitly report that nothing was saved. Supplier save/un-save controls only affect local preview state. A supplier result in search opens the supplier fixture rather than treating it as editable local stock.

## Reachability and limits

`ProductGroupList`, `AddProductGroupButton`, the older `ProductImagePreview`, and `SummaryCard` have no current primary-workspace call site. Group drilldown can still be reached by existing group-management code. `CommerceOrdersPage` is a compatibility implementation; current navigation uses the newer Sales commerce surfaces. These are not added to the preview gallery.

The WhatsApp listing preview keeps WhatsApp's recognizable message-surface styling because it depicts a customer-facing WhatsApp message, while the enclosing form follows the app theme. Responsive image proportions remain where useful; typography and routine form spacing no longer scale with the screen size in the touched product surfaces.

Live photo permissions/uploads, Firestore saves/deletion, supplier quote changes and listing creation require authenticated device/staging verification. Local tests cover presentation and existing stock/supplier contracts without making those calls. The pre-existing sale product-lookup fallback remains unchanged when a referenced product is missing.

## Verification

Verified with pinned Flutter 3.29.2: **55 focused widget/contract tests passed**, plus **12 integrated All screens gallery cases passed** (six screens at 320px with 1× and 2× text). Scoped analysis reports **0 errors and 0 warnings**; 8 pre-existing info lints remain in legacy group APIs/async handling and ProductViewModel logging. No view model or service files changed. Tests include all six new preview screens at 390 × 844 and 320 × 568 with 2× text, selected-product identity, catalogue stock filters, search keyboard/landscape layout, stock report/amount semantics, private invoice rendering, delete confirmation, and supplier catalogue/listing regressions.

The new large-text checks exposed and resolved supplier-card overflow; 2× text uses a single column with shorter images. Sale detail presentation also now accepts integer or decimal numeric product prices for formatting, preserving the value and showing an explicit unset-price label when no numeric price exists.
