# Commerce design coverage — Clean and approachable

This pass applies the chosen app direction to reachable commerce presentation:
forest hierarchy, pale green surfaces, shared type, rounded groups and controls
that wrap at large text. The audit follows the current route table and call sites.
“Changed” means local presentation code was edited; “inherited” means it uses the
shared theme or the presentation changed in an earlier pass. Neither term claims
live authenticated verification.

| Screen family | Coverage | Evidence and boundaries |
| --- | --- | --- |
| Sales → Online orders | **Changed:** rounded order cards, readable dates/statuses, amount placement that stacks on narrow screens. The combined source/date/progress filters and readiness/error states retain their existing rules. | [CombinedOnlineOrders](../lib/pages/sales/widgets/combined_online_orders.dart). Optional detail callbacks let synthetic previews open local receipt data; the default production destinations are unchanged. [OnlineCommerceHub](../lib/pages/sales/widgets/online_commerce_hub.dart) inherits the shared presentation and retains capability checks. |
| Online receipt | **Changed:** shared surface radius, fixed type scale, wrapping metadata and readable timeline/amounts. | [OnlineSaleDetailPage and OnlineSaleDetailContent](../lib/pages/sales/widgets/online_sale_detail_page.dart). The already-loaded receipt body is separate from its loader for preview/testing. Status mapping, parsing, fee figures, and authenticated fetch behavior remain intact. |
| Customer → Orders list | **Changed:** rounded order rows, shared search field, fixed date/filter typography, wrapping summary and status/collection groups. | [OrdersManagementPage](../lib/pages/ecommerce/orders_management/orders_management_page.dart) calls [OrderRow](../lib/pages/ecommerce/orders_management/widgets/order_row.dart), [OrderSearchField](../lib/pages/ecommerce/orders_management/widgets/order_search_field.dart) and [OrdersSummaryBar](../lib/pages/ecommerce/orders_management/widgets/orders_summary_bar.dart). Existing loading, retry, counts and queries remain. |
| Customer order detail | **Changed:** shared rounded Overview/Products tabs, wrapping header chips, comfortable totals/product cards and a neutral action dock. | [OrderDetailPage](../lib/pages/ecommerce/orders/order_detail_page.dart), [HeaderCard](../lib/pages/ecommerce/orders/widgets/header_card.dart), [AmountsCard](../lib/pages/ecommerce/orders/widgets/amounts_card.dart), [ProductCardEnhanced](../lib/pages/ecommerce/orders/widgets/product_card_enhanced.dart), [OrderProgressTracker](../lib/pages/ecommerce/orders/widgets/order_progress_tracker.dart). Accept/reject, delivery, collection, cash and Pay Later action policies are unchanged. |
| Wallet hub and balance | **Inherited:** the earlier shared balance/menu redesign now uses approachable tokens. **Changed:** balance history uses the same rounded activity rows for money added, message costs and payouts. | [WalletHubMenu and BillingBalancePanel](../lib/pages/wallet/wallet.dart), [WalletHistoryList](../lib/pages/wallet/tabs/unified_history_tab.dart), [WalletActivityTile](../lib/pages/wallet/widgets/wallet_activity_tile.dart). Whole-number payout amounts are converted to double only for display formatting; amounts are not recalculated. |
| Wallet message history details | **Changed:** message costs and recipient/date labels wrap; the complete message and Close action share a scrollable sheet. | [NotificationTile](../lib/pages/wallet/widgets/notification_tile.dart). This is historical content; opening the sheet does not send a message. |
| Online payments and settlement history | **Changed:** shared radii, borders and medium-weight hierarchy. **Inherited:** capability, verification and payout-state copy. | [MoneyPayoutsSection](../lib/pages/wallet/tabs/sales_balance_tab.dart). Settlement calculations, expected dates, test-only labels and setup callbacks remain intact. |
| Bank details and account verification | **Changed:** rounded summary, visible selectable values, external label/value grouping and fixed form typography. Copy actions retain their content and feedback. | [BankingDetailsSummary and verification UI](../lib/pages/wallet/tabs/banking_details_tab.dart), [banking form](../lib/pages/wallet/widgets/add_banking_details.dart). Bank choices, branch/account-type rules, identity checks and the private replay mask remain unchanged. |
| Costs and limits | **Changed:** rounded selected section tabs, shared borders/radii/type. **Inherited:** the existing fee-loading and unavailable states. | [PricingInfoTab and MessagingPricingSummary](../lib/pages/wallet/tabs/pricing_tab.dart). Live rates still come from the configured pricing source. Preview numbers are explicitly examples, not live prices. |
| Add money and payment confirmation | **Changed:** shared heading weight and surface radius in the existing form/confirmation states. **Inherited:** fields, primary controls and modal styling. | [PaystackFormScreen](../lib/pages/wallet/widgets/paystack_form.dart), [CampaignTopupVerificationScreen](../lib/pages/wallet/widgets/campaign_topup_verification_screen.dart). Channel authority, quote/confirmation order, pending-intent recovery and paid/failed/refund states are unchanged. |
| Repayment report and account suspension | **Changed:** fixed theme-aligned type and colors, scrollable page content, wrapping amount rows and full repayment references. | [FullRepaymentReportPage](../lib/pages/wallet/widgets/full_repayment_report.dart), [SuspensionPaywall](../lib/pages/wallet/widgets/suspension_paywall.dart). The report accepts an optional breakdown loader for local testing; its default remains the same configured calculation. Suspension rules, fee calculation and repayment/report callbacks remain intact. |
| Marketing and campaign history | **Inherited:** the earlier marketing/history presentation now follows the shared approachable theme. Campaign detail uses shared border, surface and type treatment. | [PromotionsPage](../lib/pages/promote/promotions_page.dart), [PromotionDetailContent](../lib/pages/promote/widgets/promotions/view_promotion/promotion_detail_content.dart). Outcome, recipient totals, retry/run-again and channel labels remain. |
| Campaign creation and review | **Changed:** stable recipient typography, rounded message cards, and a review summary/product section that stacks at 320px with 200% text. | [CustomerSelectionStep](../lib/pages/promote/widgets/promotions/create_promotions/customer_selection/customer_selection_step.dart), [ReviewAndPricingStep](../lib/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart), [MessagePreviewCard](../lib/pages/promote/widgets/message_preview_card.dart). Selection, fallback channels, cost breakdown and send confirmation policy are unchanged. |
| Template selection, creation and detail | **Changed:** rounded template picker with wrapping approval/channel labels; creation steps use stable shared-scale typography and existing controls. Detail inherits its app bar, actions and shared message preview. | [TemplatePickerCard](../lib/pages/promote/widgets/templates/template_picker_card.dart), [creation steps](../lib/pages/promote/widgets/templates/create_template/steps/basic_info_step.dart), [TemplateDetailPage](../lib/pages/promote/widgets/templates/view_template/template_detail_page.dart). Approval, disabled pending/rejected states, submission, boilerplate and deletion rules are unchanged. |
| Older duplicate surfaces | **Not presented as live screens:** no current caller was found for the old OnlineSalesList widget, OrderTile, TemplatesTab, CashAdvanceTab, InfoCenterTab or PayoutPage. Their definitions remain; shared data types/helpers can still be used by active routes. | Call-site audit across `lib/`, alongside [main routes](../lib/main.dart), [wallet destinations](../lib/pages/wallet/wallet.dart) and [promotion destinations](../lib/pages/promote/promotions_page.dart). They were not enabled or cosmetically promoted as complete flows. |
| Provider/native surfaces | **Service-owned:** hosted Paystack content, external browser/WhatsApp screens, bank authorization and native system permissions are outside the app's page styling. | [PaystackWebView](../lib/pages/wallet/widgets/paystack_webview.dart) retains the provider flow. Their app-owned entry/return UI inherits the theme; authenticated device checks are still required. |

## Interactive local examples

[commerce_design_previews.dart](../tool/commerce_design_previews.dart) exports
`Map<String, WidgetBuilder> commerceDesignPreviews()`. The eight entries return
full-screen widgets for Online orders, Online receipt, Customer order, Money
history, Bank details, Message costs, Templates and Campaign review.

They reuse production widgets with synthetic records. Order-detail taps are
redirected to the local receipt body; wallet history reads a supplied list;
payment and campaign initiation are absent. Template approval states remain
real presentation behavior: pending templates cannot be selected. Bank-copy
controls copy only the explicitly synthetic example values. No Firebase
initialization, network request, payment, campaign send or account update is
needed to review these pages.

## Verification

- **54 focused tests passed** for commerce previews, combined-order filters and
  readiness, bank copy/form/verification, wallet status notices, campaign review,
  pending-template selection, order loading and top-up confirmation states.
- The eight commerce previews were rendered and scrolled at **320px and 200%
  text**. Real local interactions cover order → receipt, approved-template
  selection and message-detail opening/closing.
- **One additional report test passed** with a supplied local breakdown:
  overview and a long repayment reference stay reachable at 320px/200% text.
- Initial scoped analysis had no errors or warnings; informational suggestions
  for changed const expressions and braces were then applied. Existing service
  and view-model lints were left untouched. Final integrated analysis and test
  counts are recorded by the main app handoff.

Evidence: [commerce preview checks](../test/commerce_design_preview_test.dart),
[report presentation check](../test/repayment_report_presentation_test.dart),
[combined orders](../test/combined_online_orders_test.dart),
[wallet hub](../test/wallet_payments_hub_test.dart),
[bank summary](../test/banking_details_summary_test.dart),
[bank form](../test/add_banking_details_page_test.dart),
[bank verification](../test/bank_account_verification_dialog_test.dart),
[promotion detail](../test/promotion_detail_content_test.dart),
[promotion action](../test/promotion_bottom_action_test.dart),
[top-up states](../test/campaign_topup_verification_screen_test.dart).

Authenticated order updates, actual bank verification/settlements, repayment
launch, payment-provider callbacks, live template approval and campaign sending
remain native/integration verification gates. No external data was read or
changed for this presentation pass.
