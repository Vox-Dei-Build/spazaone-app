import 'package:pasella/models/wallet/banking_detail_model.dart';

/// Returns the saved document ID so a newly added account is subsequently
/// updated in place. The caller owns the authorized, store-scoped callbacks.
Future<String> persistBankingDetails({
  required BankingDetails details,
  required String? documentId,
  required Future<String> Function(BankingDetails details) create,
  required Future<void> Function(String documentId, BankingDetails details)
      update,
}) async {
  if (documentId == null) return create(details);
  if (documentId.isEmpty) {
    throw StateError('A saved account needs a document ID.');
  }
  await update(documentId, details);
  return documentId;
}
