import { db, functions } from "../config/main"; // Firebase or GCP cloud function import
import { normalizePhoneNumber } from "../contact/fetchUserBalance";
import axios from "axios";



exports.runMerchantPromotion = functions.https.onRequest(async (req, res) => {
    const { merchantId, customerIds, templateId } = req.body;
  
    try {
      const userDoc = await db.collection("users").doc(merchantId).get();
      const userData = userDoc.data();
      
      const customersPromises = customerIds.map(async (customerId) => {
        const customerDoc = await db.collection("users").doc(merchantId)
                                    .collection("customers").doc(customerId).get();
        const customerData = customerDoc.data();
        
        if (!customerData.number) return;
  
        const normalizedNumber = normalizePhoneNumber(customerData.number);
        const whatsappNumber = `whatsapp:+27${normalizedNumber.slice(1)}`;
  
        const messageData = {
          to: whatsappNumber,
          templateId,
          templateParams: {
            merchant_name: userData.name,
            shop_name: userData.shopName,
            customer_name: customerData.name,
          },
          botType: "Customer",
        };
  
        await axios.post("https://us-central1-pasella-ledger.cloudfunctions.net/sendTwilioMessage", messageData);
      });
  
      await Promise.all(customersPromises);
  
      res.status(200).send({ success: true, message: "Promotion executed successfully!" });
    } catch (error) {
      console.error("Promotion Error:", error);
      res.status(500).send({ success: false, error: error.message });
    }
  });
  