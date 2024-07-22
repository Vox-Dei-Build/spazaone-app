import { DocumentData } from "firebase-admin/firestore";
import { functions, db } from "../config/main";

type ReportData = {
  startDate?: string;
  endDate?: string;
  period?: number;
  yearlyPeriod?: number;
};

type Report = {
  totalNumberofNPAs: number;
  customersWithNPAs: string[];
  nplRatio: number;
  avgRepaymentTime: number;
  creditCycle: number;
};

type CashflowImpactReport = {
  totalNumberofNPAs: number;
  customersWithNPAs: DocumentData[];
  nplRatio: number;
  cashflowImpact: number;
};

exports.generateCashflowImpactReport = functions.https.onCall(
  async (
    data: ReportData,
    context: functions.https.CallableContext,
  ): Promise<CashflowImpactReport> => {
    try {
      // Ensure the user is authenticated
      if (!context.auth) {
        console.warn("User not authenticated.");
        throw new functions.https.HttpsError(
          "unauthenticated",
          "User must be authenticated to generate a report.",
        );
      }

      const currentUserId = context.auth.uid;

      const [customerSize, customersWithNPAs] = await Promise.all([
        getTotalCustomers(currentUserId),
        fetchCustomersWithNPAsCashflowImpact(currentUserId),
      ]);

      const totalNumberofNPAs = customersWithNPAs.length;
      const nplRatio = await calculateNPLRatio(totalNumberofNPAs, customerSize);
      const cashflowImpact = customersWithNPAs.reduce(
        (sum, customer) => sum + customer.balance,
        0,
      );

      console.log(customersWithNPAs);

      return {
        totalNumberofNPAs: totalNumberofNPAs,
        customersWithNPAs: customersWithNPAs,
        nplRatio: nplRatio,
        cashflowImpact: cashflowImpact,
      };
    } catch (error) {
      console.error("Error generating report:", error);
      throw new functions.https.HttpsError(
        "internal",
        "An error occurred while generating the report.",
      );
    }
  },
);

exports.generateReport = functions.https.onCall(
  async (
    data: ReportData,
    context: functions.https.CallableContext,
  ): Promise<Report> => {
    try {
      // Ensure the user is authenticated
      if (!context.auth) {
        console.warn("User not authenticated.");
        throw new functions.https.HttpsError(
          "unauthenticated",
          "User must be authenticated to generate a report.",
        );
      }

      const currentUserId = context.auth.uid;

      const [customerSize, customersWithNPAs] = await Promise.all([
        getTotalCustomers(currentUserId),
        fetchCustomersWithNPAs(currentUserId),
      ]);

      const totalNumberofNPAs = customersWithNPAs.length;
      const nplRatio = await calculateNPLRatio(totalNumberofNPAs, customerSize);

      return {
        totalNumberofNPAs: totalNumberofNPAs,
        customersWithNPAs: customersWithNPAs,
        nplRatio: nplRatio,
        avgRepaymentTime: 0,
        creditCycle: 0,
      };
    } catch (error) {
      console.error("Error generating report:", error);
      throw new functions.https.HttpsError(
        "internal",
        "An error occurred while generating the report.",
      );
    }
  },
);

/**
 * Fetches the actual customers who are classified as Non-Performing Assets (NPAs).
 *
 * @param {string} currentUserId - The unique identifier of the current user. This is used to query the user's customers.
 * @return {Promise<DocimentData[]>} - A promise that resolves with a list of names of customers classified as NPAs. If an error occurs, it resolves with an empty list.
 * @throws Will throw an error if the `currentUserId` is invalid or if there's an issue querying the database.
 */
async function fetchCustomersWithNPAsCashflowImpact(currentUserId: string) {
  if (!currentUserId) {
    console.error("Invalid currentUserId:", currentUserId);
    return [];
  }

  try {
    const npaCustomers: DocumentData[] = [];

    const snapshot = await db
      .collection("users")
      .doc(currentUserId)
      .collection("customers")
      .where("isNPA", "==", true)
      .get();

    snapshot.forEach((doc) => {
      const customerData = doc.data();
      npaCustomers.push({
        id: doc.id,
        name: customerData.name,
        number: customerData.number,
        category: customerData.category,
        balance: customerData.balance,
        lastTransaction: customerData.lastTransaction,
        lastReminderSent: customerData.lastReminderSent,
        isNPA: customerData.isNPA,
      });
    });

    return npaCustomers;
  } catch (error) {
    console.error("Error fetching NPA customers:", error);
    throw error; // Rethrowing the error to be handled in the main function
  }
}

/**
 * Fetches the names of customers who are classified as Non-Performing Assets (NPAs).
 *
 * @param {string} currentUserId - The unique identifier of the current user. This is used to query the user's customers.
 * @return {Promise<string[]>} - A promise that resolves with a list of names of customers classified as NPAs. If an error occurs, it resolves with an empty list.
 * @throws Will throw an error if the `currentUserId` is invalid or if there's an issue querying the database.
 */
async function fetchCustomersWithNPAs(currentUserId: string) {
  if (!currentUserId) {
    console.error("Invalid currentUserId:", currentUserId);
    return [];
  }

  try {
    const npaCustomers: string[] = [];

    const snapshot = await db
      .collection("users")
      .doc(currentUserId)
      .collection("customers")
      .where("isNPA", "==", true)
      .get();

    snapshot.forEach((doc) => {
      npaCustomers.push(doc.data().name);
    });

    return npaCustomers;
  } catch (error) {
    console.error("Error fetching NPA customers:", error);
    throw error; // Rethrowing the error to be handled in the main function
  }
}

/**
 * Fetches the total number of customers for a given user.
 *
 * @param {string} currentUserId - The ID of the user for whom the total number of customers is to be fetched.
 * @return {Promise<number>} - Returns a promise that resolves to the total number of customers.
 * @throws {Error} - Throws an error if there's an issue fetching the data or if the `totalCustomers` field is missing.
 */
async function getTotalCustomers(currentUserId: string): Promise<number> {
  try {
    const userDoc = await db.collection("users").doc(currentUserId).get();
    const userData = userDoc.data();

    if (
      !userData ||
      !userData.balanceData ||
      userData.balanceData.totalCustomers === undefined
    ) {
      console.error(
        `totalCustomers field not found inside balanceData for user ${currentUserId}.`,
      );
      return 0; // Return a default value of 0 if the field doesn't exist
    }

    return userData.balanceData.totalCustomers;
  } catch (error) {
    console.error(
      `Error fetching totalCustomers for user ${currentUserId}:`,
      error,
    );
    throw error;
  }
}

/**
 * Calculates the NPL ratio.
 *
 * @param {number} totalNumberofNPAs - The total number of NPAs.
 * @param {number} totalNumberOfCustomers - The total amount for loans.
 * @return {Promise<number>} - A promise that resolves with the calculated NPL ratio.
 */
async function calculateNPLRatio(
  totalNumberofNPAs: number,
  totalNumberOfCustomers: number,
): Promise<number> {
  if (totalNumberOfCustomers === 0) {
    return 0.0; // To avoid division by zero
  }
  const NPLRatio = (totalNumberofNPAs / totalNumberOfCustomers) * 100;
  return parseFloat(NPLRatio.toFixed(2));
}
