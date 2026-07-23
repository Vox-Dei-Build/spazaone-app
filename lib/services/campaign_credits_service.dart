import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Server-authorized campaign-credit mutations.
///
/// The operation id is generated before the network call, so an SDK/network
/// retry cannot debit the same message twice.
class CampaignCreditsService {
  CampaignCreditsService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  Future<void> debit({
    required String storeId,
    required double amount,
    required String reason,
  }) async {
    final operationId = _firestore.collection('_operationIds').doc().id;
    await _functions.httpsCallable('debitCampaignCredits').call({
      'storeId': storeId,
      'amount': amount,
      'operationId': operationId,
      'reason': reason,
    });
  }
}
