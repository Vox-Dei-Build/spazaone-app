import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/auth/login/login.dart';
import 'package:pasella/services/account_deletion_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  static const id = '/deleteAccount';

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _confirmationController = TextEditingController();
  final AccountDeletionService _service = AccountDeletionService.instance;

  bool _isLoading = false;
  String? _errorMessage;

  bool get _isConfirmed {
    return _confirmationController.text.trim().toUpperCase() == 'DELETE';
  }

  @override
  void initState() {
    super.initState();
    _confirmationController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    var navigatedAway = false;

    try {
      await _service.deleteAccount(context);
      if (!mounted) return;
      navigatedAway = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Your Spaza One account has been deleted.')),
      );
      Navigator.of(context)
          .pushNamedAndRemoveUntil(LoginPage.id, (route) => false);
    } on AccountDeletionCancelledException {
      // User backed out of reauthentication – no error feedback needed.
    } on AccountDeletionException catch (error) {
      if (!mounted) return;
      _errorMessage = error.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      _errorMessage = 'Something went wrong, please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to delete account. Please try again.')),
      );
    } finally {
      if (!navigatedAway && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Delete Account'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deleting your account is permanent. This will:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const _BulletPoint(
                    text:
                        'Remove your shop, products, sales and customer history.'),
                const _BulletPoint(
                    text:
                        'Delete all stored media, promotions and wallet records associated with your account.'),
                const _BulletPoint(
                    text:
                        'Sign you out of Spaza One and prevent reuse of this account.'),
                const SizedBox(height: 24),
                Text(
                  'To confirm, type DELETE below and tap the button. You may be asked to verify your phone number or password again for security.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmationController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        !_isLoading && _isConfirmed ? _handleDelete : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_forever),
                    label: Text(
                      _isLoading ? 'Deleting...' : 'Delete my account',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
