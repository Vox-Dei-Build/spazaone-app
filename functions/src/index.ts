// Start writing functions
// https://firebase.google.com/docs/functions/typescript
/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

/* ---- Merchant Android App ---- */
export * from "./config/main";
export * from "./ledger/ledger";
export * from "./ledger/onTransactionAdded";
export * from "./reports/business_metrics";
export * from "./reports/scheduledTasks/updateNPAStatus";
export * from "./contact/addPayment";
export * from "./contact/fetchUserBalance";
export * from "./notifications/retention_notifications";
export * from "./notifications/non_payment_notifications";
export * from "./stock/scheduledTasks/scheduledLowStockCheck";
export * from "./payments/paystack/createPaystackTransaction";
export * from "./payments/paystack/verifyPaystackTransaction";
export * from "./payments/paystack/getPaystackQuote";
/* Bot */
export * from "./customer_hub/fetchCustomerAndMerchantDetails";
export * from "./customer_hub/sendPromoToActiveCustomers";
export * from "./bots/twillio-whatsapp-notification-bot";

/* ---- Customer Bot ---- */
export * from "./community/receive-whatsapp";
export * from "./community/status-callback";
export * from "./customer_hub/addCredit";
export * from "./customer_hub/fetchUserBalance";
export * from "./customer_hub/fetchTransactionHistory";

/* ---- Merchant Bot ---- */
export * from "./merchant_hub/order/airtime/createAirtimeOrder";
export * from "./merchant_hub/fetchMerchantDetails";
export * from "./merchant_hub/order/airtime/getMerchantAirtimeOrders";
export * from "./merchant_hub/order/electricity/createElectricityOrder";
export * from "./merchant_hub/order/electricity/getMerchantElectricityOrders";
export * from "./merchant_hub/order/updateOrderStatus";
export * from "./merchant_hub/logUnreadMessage";
export * from "./merchant_hub/markMessagesAsRead";
export * from "./merchant_hub/submitWhatsAppTemplate";
export * from "./merchant_hub/checkTwilioApprovalStatuses";
export * from "./merchant_hub/deleteTwilioTemplate";
export * from "./merchant_hub/runMerchantPromotion";

/* ---- Ecommerce ---- */
export * from "./ecommerce/getProducts";
export * from "./ecommerce/addToCart";
export * from "./ecommerce/removeFromCart";
export * from "./ecommerce/getCart";
export * from "./ecommerce/checkoutCart";
export * from "./ecommerce/confirmSalePayment";
export * from "./ecommerce/getSaleStatus";
export * from "./ecommerce/getCustomerOrders";
export * from "./ecommerce/updateCartItemQuantity";
export * from "./ecommerce/getMerchantSales";
export * from "./ecommerce/updateOrderPayment";
export * from "./ecommerce/getOrderById";
export * from "./ecommerce/notifyOrderEvent";
export * from "./ecommerce/orderNotification";
export * from "./ecommerce/getOpenSale";
export * from "./ecommerce/cartSig";
export * from "./ecommerce/finalizeOnlinePaid";
export * from "./ecommerce/onSaleCancelledNotify";
export * from "./ecommerce/cancelOrder";
export * from "./ecommerce/finalizeOnlinePaid";
export * from "./ecommerce/getOnlineSalesFromLedger";
