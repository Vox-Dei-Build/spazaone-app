import { functions } from "../config/main";
import * as nodemailer from "nodemailer";
// Configure your email transport
const mailTransport = nodemailer.createTransport({
  host: "live.smtp.mailtrap.io",
  port: 587,
  auth: {
    user: functions.config().email.adminlogin,
    pass: functions.config().email.adminpass,
  },
});

exports.requestPayout = functions.firestore
  .document("payoutRequests/{requestId}")
  .onCreate(async (snap, context) => {
    const payoutRequest = snap.data();
    const merchantId = payoutRequest.merchantId;
    const amount = payoutRequest.amount;

    try {
      const SPEmail = "tsepo.ntsaba@thedelta.io";

      // Prepare email
      const mailOptions = {
        from: `Pasella <mailtrap@demomailtrap.com>`,
        to: SPEmail,
        subject: `Payout Request from: ${merchantId}`,
        text: `A payout of ${amount} has been requested by merchant ${merchantId}. Please review and process.`,
      };

      // Send email
      await mailTransport.sendMail(mailOptions);
      console.log("Email sent to:", SPEmail);

      // Update payout request status to 'notified' or similar
      await snap.ref.update({ status: "notified" });
    } catch (error) {
      console.log("Error processing payout request:", error);
    }
  });
