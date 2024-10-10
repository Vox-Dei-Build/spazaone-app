/**
 * TemplateMessages
 *
 * Contains static template messages for various types of communication with customers, including credit confirmation, payment confirmation, onboarding, and reminders.
 */
export class TemplateMessages {
  /**
   * Credit confirmation message template.
   *
   * @type {string}
   */
  static creditConfirmationMessage = `
  Dear {customerName}, your recent Credit of -{amount} at {shopName} has been recorded.
  
  Your current balance is {balance}. Thank you for trusting {shopName}'s business!
  
  From {shopName}
  `;

  /**
   * Payment confirmation message template.
   *
   * @type {string}
   */
  static paymentConfirmationMessage = `
  Dear {customerName}, your recent Payment of +{amount} at {shopName} has been recorded.
  
  Your current balance is {balance}. Thank you for paying {shopName}'s business and for being reliable!
  
  From {shopName}
  `;

  /**
   * Onboarding message template.
   *
   * @type {string}
   */
  static onboardingMessage = `
  Welcome to {shopName}, {customerName}! No more books! Your account with {shopName} is now online.
  
  Your current balance is R0,00. Thank you again for choosing {shopName}'s business!
  
  From {shopName}
  `;

  /**
   * Reminder message template for payment due.
   *
   * @type {string}
   */
  static reminderMessage = `
  Hi {customerName}, your balance at {shopName} of {balance} is due.
  
  Please keep up to date with your payments and join the 98% of {shopName}'s customers who pay back on time or penalties will be charged.
  
  From {shopName}
  `;
}
