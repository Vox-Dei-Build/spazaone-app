import 'package:flutter/material.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/widgets/private_region.dart';

class EditCustomerPage extends StatefulWidget {
  const EditCustomerPage({super.key, required this.viewModel});

  final CustomerManagementViewModel viewModel;

  @override
  State<EditCustomerPage> createState() => _EditCustomerPageState();
}

class _EditCustomerPageState extends State<EditCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.viewModel.updateCustomerDetails(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final viewModel = widget.viewModel;
        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: const CustomAppBar(title: 'Edit customer'),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: viewModel.isLoading ? null : _save,
                icon: viewModel.isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(viewModel.isLoading ? 'Saving…' : 'Save changes'),
              ),
            ),
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  28 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PhotoEditor(viewModel: viewModel),
                    const SizedBox(height: 28),
                    Text(
                      'Customer details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keep the mobile number up to date for messages and payment requests.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 18),
                    PrivateRegion(
                      child: CustomTextField(
                        controller: viewModel.nameController,
                        hintText: 'Customer name',
                        prefixIcon: Icons.person_outline,
                        label: 'Name *',
                        textInputType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                        maxLength: 40,
                        validator: (_) => viewModel.validateName(),
                      ),
                    ),
                    PrivateRegion(
                      child: CustomTextField(
                        controller: viewModel.numberController,
                        hintText: 'SA mobile number',
                        prefixIcon: Icons.phone_outlined,
                        label: 'Mobile number (optional)',
                        textInputType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).unfocus(),
                        maxLength: 20,
                        validator: (_) => viewModel.validateNumber(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoEditor extends StatelessWidget {
  const _PhotoEditor({required this.viewModel});

  final CustomerManagementViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: viewModel.isLoading
            ? null
            : () => viewModel.handleImagePick(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              profilePicture(
                context,
                viewModel.nameController.text,
                viewModel.profileImageDisplayUrl,
                viewModel.numberController.text,
                false,
                displayIcons: false,
                radius: 42,
                profileImage: viewModel.profileImage,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      viewModel.hasPendingProfileImage
                          ? 'New photo selected'
                          : 'Customer photo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      viewModel.hasPendingProfileImage
                          ? 'It will be uploaded when you save.'
                          : 'Tap to add or change the photo.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
