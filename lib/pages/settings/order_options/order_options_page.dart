import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/merchant_ordering_options_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

typedef OrderingOptionsLoader = Future<MerchantOrderingOptions> Function();
typedef OrderingOptionsSaver = Future<MerchantOrderingOptions> Function({
  required bool payLaterEnabled,
  required bool deliveryEnabled,
  required int deliveryFlatFeeMinor,
  required String deliveryServiceAreaText,
});

class OrderOptionsPage extends StatefulWidget {
  OrderOptionsPage({
    super.key,
    OrderingOptionsLoader? loader,
    OrderingOptionsSaver? saver,
  })  : loader = loader ?? MerchantOrderingOptionsService().load,
        saver = saver ?? MerchantOrderingOptionsService().save;

  final OrderingOptionsLoader loader;
  final OrderingOptionsSaver saver;

  @override
  State<OrderOptionsPage> createState() => _OrderOptionsPageState();
}

class _OrderOptionsPageState extends State<OrderOptionsPage> {
  final _formKey = GlobalKey<FormState>();
  final _fee = TextEditingController();
  final _area = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _payLater = false;
  bool _delivery = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final options = await widget.loader();
      if (!mounted) return;
      setState(() {
        _payLater = options.payLaterEnabled;
        _delivery = options.deliveryEnabled;
        _fee.text = (options.deliveryFlatFeeMinor / 100).toStringAsFixed(2);
        _area.text = options.deliveryServiceAreaText;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amount = double.tryParse(_fee.text.trim()) ?? 0;
      await widget.saver(
        payLaterEnabled: _payLater,
        deliveryEnabled: _delivery,
        deliveryFlatFeeMinor: (amount * 100).round(),
        deliveryServiceAreaText: _area.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order options saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _message(Object error) {
    if (error is FirebaseFunctionsException &&
        error.message?.trim().isNotEmpty == true) {
      return error.message!.trim();
    }
    return 'Order options could not be loaded. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Order options'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'Choose what customers can request',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pickup is always available. Delivery and Pay Later stay hidden until you turn them on.',
                  ),
                  const SizedBox(height: 18),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.store_mall_directory_outlined),
                      title: Text('Pickup'),
                      subtitle: Text('Always available'),
                      trailing: Icon(Icons.check_circle_outline),
                    ),
                  ),
                  Card(
                    child: SwitchListTile(
                      key: const ValueKey('pay-later-option'),
                      secondary: const Icon(Icons.schedule_outlined),
                      title: const Text('Pay Later'),
                      subtitle: const Text(
                        'Each request still needs your approval before fulfilment.',
                      ),
                      value: _payLater,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _payLater = value),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          key: const ValueKey('delivery-option'),
                          secondary: const Icon(Icons.local_shipping_outlined),
                          title: const Text('Delivery'),
                          subtitle: const Text(
                            'Online delivery orders wait for your address approval before payment.',
                          ),
                          value: _delivery,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _delivery = value),
                        ),
                        if (_delivery)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                TextFormField(
                                  key: const ValueKey('delivery-fee-field'),
                                  controller: _fee,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Flat delivery fee',
                                    prefixText: 'R ',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    final parsed =
                                        double.tryParse(value?.trim() ?? '');
                                    if (parsed == null || parsed < 0) {
                                      return 'Enter a valid delivery fee.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  key: const ValueKey('service-area-field'),
                                  controller: _area,
                                  maxLength: 240,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    labelText: 'Delivery area',
                                    hintText:
                                        'For example: within 5 km of the shop',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) =>
                                      (value?.trim().isEmpty ?? true)
                                          ? 'Describe where you deliver.'
                                          : null,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const ValueKey('order-options-error'),
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('save-order-options'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save order options'),
                  ),
                ],
              ),
            ),
    );
  }
}
