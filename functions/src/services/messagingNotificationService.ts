import * as admin from "firebase-admin";
import { CurrencyUtil } from "../utils/currencyUtil";
import {
  fetchAndFormatPhoneNumber,
  fetchShopNameForUser,
  isValidSAPhoneNumber,
} from "../utils/phoneUtils";
import twilio from "twilio/lib/index";

/**
 * MessagingNotificationService
 *
 * Handles the sending of various notification messages such as confirmation, onboarding, and reminder messages
 * via Twilio using WhatsApp or SMS.
 */
class MessagingNotificationService {
  private welcomeMessage: string;
  private creditTransaction: string;
  private paymentTransaction: string;
  private reminderMessage: string;

  /**
   * Constructor
   *
   */
  constructor() {
    this.welcomeMessage = process.env.TWILIO_WELCOME_MESSAGE_TID || "";
    this.creditTransaction = process.env.TWILIO_CREDIT_TRANSACTION_TID || "";
    this.paymentTransaction = process.env.TWILIO_PAYMENT_TRANSACTION_TID || "";
    this.reminderMessage = process.env.TWILIO_REMINDER_MESSAGE_TID || "";
  }

  /**
   * Sends a formatted message via Twilio (WhatsApp or SMS).
   *
   * @param {string} currentUserId - The ID of the current user (merchant).
   * @param {string} customerId - The ID of the customer receiving the message.
   * @param {string} customerName - The name of the customer.
   * @param {string} message - The message content to be sent.
   * @param {string} templateSid - The Twilio template SID for the message.
   * @param {string | null} mobileNumber - The customer's mobile number.
   * @param {string | null} amount - The amount involved in the transaction (formatted).
   * @return {Promise<void>} - Sends a message and logs it in Firestore under the reminders collection.
   */
  async sendFormattedMessage(
    currentUserId: string,
    customerId: string,
    customerName: string,
    message: string,
    templateSid: string,
    mobileNumber: string | null,
    amount: string | null,
  ): Promise<void> {
    try {
      const accountSid = process.env.TWILIO_ACCOUNT_SID; // Your Account SID from www.twilio.com/console
      const authToken = process.env.TWILIO_AUTH_TOKEN;
      const messagingServiceID =
        process.env.TWILIO_CUSTOMER_MESSAGING_SERVICE_SID;
      const client = twilio(accountSid, authToken);
      const phoneNumberPromise = fetchAndFormatPhoneNumber(
        currentUserId,
        customerId,
      );
      const shopNamePromise = fetchShopNameForUser(currentUserId);
      const balancePromise = CurrencyUtil.fetchCurrentBalanceForCustomer(
        currentUserId,
        customerId,
      );

      const [phoneNumber, shopName, balance] = await Promise.all([
        phoneNumberPromise,
        shopNamePromise,
        balancePromise,
      ]);

      if (isValidSAPhoneNumber(phoneNumber) && phoneNumber) {
        const formattedBalance = CurrencyUtil.format(balance);

        const templateParams = {
          customerName,
          amount,
          shopName: shopName || "SpazaOne",
          balance: formattedBalance,
        };

        const messageResponse = await client.messages.create({
          to: `whatsapp:${phoneNumber}`, // Phone number to send the message to (WhatsApp/SMS)
          from: messagingServiceID, // Your Twilio phone number or WhatsApp sender ID
          contentVariables: templateParams
            ? JSON.stringify(templateParams)
            : "", // Template params for dynamic placeholders
          messagingServiceSid: messagingServiceID, // Your Messaging Service SID if applicable
          contentSid: templateSid, // The template ID (Content SID) for the pre-approved message template
        });

        console.log(messageResponse);

        await admin
          .firestore()
          .collection("users")
          .doc(currentUserId)
          .collection("customers")
          .doc(customerId)
          .collection("reminders")
          .add({
            message,
            dateSent: admin.firestore.Timestamp.now(),
          });
      }
    } catch (e) {
      console.error("Error while sending SMS, queuing for later:", e);
    }
  }

  /**
   * Sends a confirmation message (Credit or Payment) to the customer.
   *
   * @param {string} currentUserId - The ID of the current user (merchant).
   * @param {string} customerId - The ID of the customer receiving the message.
   * @param {string} transactionType - The type of transaction ("Credit" or "Payment").
   * @param {number} amount - The amount involved in the transaction.
   * @param {string} customerName - The name of the customer.
   * @param {string | null} mobileNumber - The customer's mobile number.
   * @return {Promise<void>} - Sends a confirmation message.
   */
  async sendConfirmationMessage(
    currentUserId: string,
    customerId: string,
    transactionType: string,
    amount: number,
    customerName: string,
    mobileNumber: string | null,
  ): Promise<void> {
    try {
      let message = "";
      let templateSid = "";

      if (transactionType === "Credit") {
        templateSid = this.creditTransaction;
        message = `Dear ${customerName}, your recent Credit of -${CurrencyUtil.format(amount)} has been recorded.`;
      } else {
        templateSid = this.paymentTransaction;
        message = `Dear ${customerName}, your recent Payment of +${CurrencyUtil.format(amount)} has been recorded.`;
      }

      await this.sendFormattedMessage(
        currentUserId,
        customerId,
        customerName,
        message,
        templateSid,
        mobileNumber,
        CurrencyUtil.format(amount),
      );
    } catch (e) {
      console.error("Error occurred while sending confirmation SMS:", e);
    }
  }

  /**
   * Sends an onboarding message to a new customer.
   *
   * @param {string} currentUserId - The ID of the current user (merchant).
   * @param {string} customerId - The ID of the customer receiving the message.
   * @param {string} customerName - The name of the customer.
   * @param {string | null} mobileNumber - The customer's mobile number.
   * @return {Promise<void>} - Sends an onboarding message.
   */
  async sendOnboardingMessage(
    currentUserId: string,
    customerId: string,
    customerName: string,
    mobileNumber: string | null,
  ): Promise<void> {
    try {
      const templateSid = this.welcomeMessage;
      await this.sendFormattedMessage(
        currentUserId,
        customerId,
        customerName,
        "Welcome to our shop!",
        templateSid,
        mobileNumber,
        "0",
      );
    } catch (e) {
      console.error("Error occurred while sending onboarding SMS:", e);
    }
  }

  /**
   * Sends a reminder message to the customer.
   *
   * @param {string} currentUserId - The ID of the current user (merchant).
   * @param {string} customerId - The ID of the customer receiving the message.
   * @param {string} customerName - The name of the customer.
   * @param {string | null} mobileNumber - The customer's mobile number.
   * @return {Promise<void>} - Sends a reminder message.
   */
  async sendReminderMessage(
    currentUserId: string,
    customerId: string,
    customerName: string,
    mobileNumber: string | null,
  ): Promise<void> {
    try {
      const templateSid = this.reminderMessage;
      await this.sendFormattedMessage(
        currentUserId,
        customerId,
        customerName,
        "Your payment is due.",
        templateSid,
        mobileNumber,
        "0",
      );
    } catch (e) {
      console.error("Error occurred while sending reminder SMS:", e);
    }
  }
}

export { MessagingNotificationService };
