import 'dart:convert';
import 'package:http/http.dart' as http;

class PaystackService {
  static const String _baseUrl =
      "https://us-central1-pasella-ledger.cloudfunctions.net/createPaystackTransaction";

  /// Initializes a Paystack transaction
  static Future<String?> initializeTransaction(
      String userId, double amount, String email) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId, "amount": amount, "email": email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["authorizationUrl"];
      } else {
        print("Paystack Error: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error initializing transaction: $e");
      return null;
    }
  }
}
