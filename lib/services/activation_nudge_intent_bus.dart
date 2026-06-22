enum ActivationNudgeAction {
  addCustomer,
  addTenCustomers,
  addProduct,
  shareOrderingLink,
  linkProductTransaction,
  recordFirstTransaction,
}

class ActivationNudgeIntent {
  const ActivationNudgeIntent({
    required this.action,
    this.customerId,
    this.nudgeType,
    this.nudgeId,
  });

  final ActivationNudgeAction action;
  final String? customerId;
  final String? nudgeType;
  final String? nudgeId;

  static ActivationNudgeIntent? fromUri(
    Uri uri, {
    Map<String, dynamic> data = const {},
  }) {
    final actionValue = uri.queryParameters['activation'] ??
        uri.queryParameters['action'] ??
        data['activationAction']?.toString() ??
        data['action']?.toString();
    final action = _parseAction(actionValue);
    if (action == null) return null;

    String? optional(String key) {
      final value = uri.queryParameters[key] ?? data[key]?.toString();
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    }

    return ActivationNudgeIntent(
      action: action,
      customerId: optional('customerId'),
      nudgeType: optional('nudgeType'),
      nudgeId: optional('nudgeId'),
    );
  }

  static ActivationNudgeAction? _parseAction(String? value) {
    switch (value) {
      case 'add_first_customer':
      case 'add_customer':
        return ActivationNudgeAction.addCustomer;
      case 'add_ten_customers':
        return ActivationNudgeAction.addTenCustomers;
      case 'add_first_product':
      case 'add_product':
        return ActivationNudgeAction.addProduct;
      case 'share_ordering_link':
      case 'open_ordering_link':
        return ActivationNudgeAction.shareOrderingLink;
      case 'link_product_transaction':
        return ActivationNudgeAction.linkProductTransaction;
      case 'record_first_transaction':
        return ActivationNudgeAction.recordFirstTransaction;
    }
    return null;
  }
}

class ActivationNudgeIntentBus {
  ActivationNudgeIntentBus._();

  static final ActivationNudgeIntentBus instance = ActivationNudgeIntentBus._();

  ActivationNudgeIntent? _pending;

  void set(ActivationNudgeIntent intent) {
    _pending = intent;
  }

  ActivationNudgeIntent? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
