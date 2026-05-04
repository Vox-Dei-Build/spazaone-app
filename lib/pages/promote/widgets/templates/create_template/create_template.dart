import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/force_boilerplate.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/basic_info_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/content_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/review_step.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

enum CreateTemplateStep {
  basicInfo,
  content,
  review,
}

class CreateTemplatePage extends StatefulWidget {
  final PromotionsViewModel viewModel;

  const CreateTemplatePage({super.key, required this.viewModel});

  @override
  State<CreateTemplatePage> createState() => _CreateTemplatePageState();
}

class _CreateTemplatePageState extends State<CreateTemplatePage> {
  final _formKey = GlobalKey<FormState>();
  final _templateNameController = TextEditingController();
  final _whatsappContentController = TextEditingController();
  final _smsContentController = TextEditingController();
  final _mediaUrlController = TextEditingController();
  bool showChannelError = false;

  CreateTemplateStep currentStep = CreateTemplateStep.basicInfo;
  bool includeWhatsApp = true;
  bool includeSMS = true;
  bool saving = false;

  DynamicPricingService? _pricingService;
  double? _whatsappPrice;
  double? _smsPricePerSegment;
  int _smsSegments = 1;
  final PhotoUploadUtil _photoUtil = PhotoUploadUtil();
  bool uploadingImage = false;
  PromotionsViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _pricingService = await DynamicPricingService.initialize();
      setState(() {
        _whatsappPrice = _pricingService?.whatsappPromotionPrice;
        _smsPricePerSegment = _pricingService?.smsReminderTemplatePrice;
      });
    });
  }

  void nextStep() {
    // Always grab the form’s current validity & channel state
    final isFormValid = _formKey.currentState?.validate() ?? false;

    // STEP 1: Basic Info → require name & at least one channel
    if (currentStep == CreateTemplateStep.basicInfo) {
      if (!isFormValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a template name.')),
        );
        return;
      }
      // Sanitize the name when moving to the next step
      final sanitized = _sanitizeTemplateName(_templateNameController.text);
      if (sanitized != _templateNameController.text) {
        _templateNameController.text = sanitized;
      }
    }

    // STEP 2: Content → require non‑empty body for each chosen channel
    if (currentStep == CreateTemplateStep.content) {
      if (_whatsappContentController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message body is required.')),
        );
        return;
      }
    }

    // If we passed validation, clear any channel error flag
    setState(() {
      showChannelError = false;
      currentStep = CreateTemplateStep.values[currentStep.index + 1];
    });
  }

  void previousStep() {
    if (currentStep.index == 0) return;
    setState(() {
      currentStep = CreateTemplateStep.values[currentStep.index - 1];
    });
  }

  void _calculateSmsPricing(String text) {
    setState(() {
      _smsSegments = SMSPricingUtil.calculateSegments(text);
    });
  }

  String _sanitizeTemplateName(String input) {
    String s = input.toLowerCase();
    s = s.replaceAll(RegExp(r'[\s-]+'), '_');
    s = s.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);

    final userId = FirebaseAuth.instance.currentUser?.uid ?? "";
    final now = Timestamp.now();

    // Apply boilerplate (Hi/From) before extracting variables so defaults are included
    final whatsappContent =
        includeWhatsApp ? forceBoilerplate(_whatsappContentController.text) : '';
    final smsContent = _smsContentController.text;

    final variables = <String>{};
    final exp = RegExp('{{\s*([A-Za-z0-9_]+)\s*}}');
    for (final match in exp.allMatches(whatsappContent + smsContent)) {
      variables.add(match.group(1)!);
    }

    final data = {
      'userId': userId,
      'name': _sanitizeTemplateName(_templateNameController.text.trim()),
      'contentType': 'text',
      'variables': variables.toList(),
      'default': false,
      'active': true,
      'createdAt': now,
      'channels': {
        if (includeWhatsApp)
          'whatsapp': {
            'templateContent': whatsappContent,
            'mediaUrl': _mediaUrlController.text.trim().isEmpty
                ? null
                : _mediaUrlController.text.trim(),
            'buttons': [],
            'approved': false,
            'submittedAt': now,
          },
        if (includeSMS)
          'sms': {
            'templateContent': smsContent,
          },
      }
    };

    try {
      await FirebaseFirestore.instance
          .collection('messagingTemplates')
          .add(data);

      // Fire‐and‐forget the reload so we don't hold up the pop
      widget.viewModel.loadTemplatesData();

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Failed to save template: $e");
    } finally {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Create Promotion Template',
      ),
      body: Padding(
        padding: LayoutConstants.padding10Horizontal,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(child: _buildStepContent()),
              _buildNavigationButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (currentStep) {
      case CreateTemplateStep.basicInfo:
        return BasicInfoStep(
          templateNameController: _templateNameController,
          showChannelError: showChannelError, // 👈 Add this
        );

      case CreateTemplateStep.content:
        return ContentStep(
          includeWhatsApp: includeWhatsApp,
          includeSMS: includeSMS,
          whatsappContentController: _whatsappContentController,
          smsContentController: _smsContentController,
          mediaUrlController: _mediaUrlController,
          photoUtil: _photoUtil,
          uploadingImage: uploadingImage,
          onImageUploadingChanged: (val) =>
              setState(() => uploadingImage = val),
          whatsappPrice: _whatsappPrice,
          smsPricePerSegment: _smsPricePerSegment,
          smsSegments: _smsSegments,
          onSmsPricingUpdate: _calculateSmsPricing,
          shopName: viewModel.shopName,
        );
      case CreateTemplateStep.review:
        return ReviewStep(
          templateName: _templateNameController.text,
          whatsappContent: _whatsappContentController.text,
          smsContent: _smsContentController.text,
          mediaUrl: _mediaUrlController.text,
          includeSMS: includeSMS,
          includeWhatsApp: includeWhatsApp,
          whatsappPrice: _whatsappPrice,
          smsPricePerSegment: _smsPricePerSegment,
          smsSegments: _smsSegments,
          shopName: viewModel.shopName,
        );
    }
  }

  // 1) Remove any calls to validate() in build:
  Widget _buildNavigationButtons() {
    final isLast = currentStep == CreateTemplateStep.review;
    final name = _templateNameController.text.trim();
    final nameValid = name.isNotEmpty; // Regex removed; we sanitize later

    final channelValid = includeWhatsApp || includeSMS;
    final whatsappFilled = _whatsappContentController.text.trim().isNotEmpty;
    final smsFilled = _smsContentController.text.trim().isNotEmpty;
    final contentValid =
        (!includeWhatsApp || whatsappFilled) && (!includeSMS || smsFilled);

    final canProceed = currentStep == CreateTemplateStep.basicInfo
        ? (nameValid && channelValid)
        : currentStep == CreateTemplateStep.content
            ? contentValid
            : true;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (currentStep != CreateTemplateStep.basicInfo)
          OutlinedButton(onPressed: previousStep, child: const Text('Back')),
        ElevatedButton(
          onPressed: saving || !canProceed
              // 2) On tap, run real Form validation before moving on
              ? null
              : () {
                  if (currentStep == CreateTemplateStep.basicInfo) {
                    // validate the form now to show errors if any
                    if (!_formKey.currentState!.validate()) {
                      setState(() => showChannelError = !channelValid);
                      return;
                    }
                    nextStep();
                  } else if (currentStep == CreateTemplateStep.content) {
                    nextStep();
                  } else {
                    _saveTemplate();
                  }
                },
          child: saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isLast ? 'Save & Submit' : 'Next'),
        ),
      ],
    );
  }
}
