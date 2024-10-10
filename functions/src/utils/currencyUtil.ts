import { format as formatCurrency } from "currency-formatter"; // Using currency-formatter package
import { db } from "../config/main";
import { Timestamp } from "firebase-admin/firestore";

/**
 * CurrencyUtil
 *
 * Utility class for formatting currency and calculating customer balances based on transaction data.
 */
export class CurrencyUtil {
  /**
   * Formats a given amount into South African Rand (ZAR) currency format.
   *
   * @param {number} amount - The amount to format.
   * @return {string} - The formatted currency string.
   */
  static format(amount: number): string {
    return formatCurrency(amount, { code: "ZAR" });
  }

  /**
   * Fetches the current balance for a customer by calculating it from their transaction history.
   *
   * @param {string} currentUserId - The user ID (merchant).
   * @param {string} customerId - The customer ID.
   * @return {Promise<number>} - The calculated customer balance.
   */
  static async fetchCurrentBalanceForCustomer(
    currentUserId: string,
    customerId: string,
  ): Promise<number> {
    const transactionsList = await CurrencyUtil.fetchTransactionsForCustomer(
      currentUserId,
      customerId,
    );
    return CurrencyUtil.calculateBalance(transactionsList);
  }

  /**
   * Fetches transactions for a customer from Firestore.
   *
   * @param {string} currentUserId - The user ID (merchant).
   * @param {string} customerId - The customer ID.
   */
  static async fetchTransactionsForCustomer(
    currentUserId: string,
    customerId: string,
  ): Promise<Array<{ [key: string]: any }>> {
    const querySnapshot = await db
      .collection("users")
      .doc(currentUserId)
      .collection("customers")
      .doc(customerId)
      .collection("transactions")
      .get();

    return querySnapshot.docs.map((doc: any) => {
      const data = doc.data() as { [key: string]: any };
      data["id"] = doc.id;
      if (data["date"] instanceof Timestamp) {
        data["date"] = (data["date"] as Timestamp).toDate().toISOString();
      }
      return data;
    });
  }

  /**
   * Calculates the balance based on transaction data.
   *
   * @param {any} transactionsList - The list of transactions.
   * @return {number} - The calculated balance.
   */
  static calculateBalance(
    transactionsList: Array<{ [key: string]: any }>,
  ): number {
    return transactionsList.reduce((balance, transaction) => {
      if (transaction.type === "Credit") {
        return balance - transaction.amount;
      } else if (transaction.type === "Debit") {
        return balance + transaction.amount;
      }
      return balance;
    }, 0);
  }
}
