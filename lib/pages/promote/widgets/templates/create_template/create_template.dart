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
    final isFormValid = _formKey.currentState?.validate() ?? false;
    final isChannelValid = includeWhatsApp || includeSMS;

    setState(() => showChannelError = !isChannelValid);

    if (isFormValid && isChannelValid) {
      setState(() {
        currentStep = CreateTemplateStep.values[currentStep.index + 1];
      });
    }
  }

  void previousStep() {
    if (currentStep.index == 0) return;
    setState(() {
      currentStep = CreateTemplateStep.values[currentStep.index - 1];
    });
  }

  void _calculateSmsPricing(String text) {
    final isUnicode = text.runes.any((r) => r > 127);
    final segmentLength = isUnicode ? 70 : 160;
    setState(() {
      _smsSegments = text.length <= segmentLength
          ? 1
          : (text.length / (segmentLength - 7)).ceil();
    });
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);

    final userId = FirebaseAuth.instance.currentUser?.uid ?? "";
    final now = Timestamp.now();
    final variables = <String>{};

    final whatsappContent = _whatsappContentController.text;
    final smsContent = _smsContentController.text;

    RegExp exp = RegExp(r'{{(.*?)}}');
    for (final match in exp.allMatches(whatsappContent + smsContent)) {
      variables.add(match.group(1)!.trim());
    }

    final data = {
      'userId': userId,
      'name': _templateNameController.text.trim(),
      'contentType': 'text',
      'variables': variables.toList(),
      'default': false,
      'active': true,
      'createdAt': now,
      'channels': {
        if (includeWhatsApp)
          'whatsapp': {
            'templateContent': forceBoilerplate(whatsappContent),
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
      if (context.mounted) Navigator.pop(context);
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
        padding: LayoutConstants.padding20Horizontal,
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

  Widget _buildNavigationButtons() {
    final isLastStep = currentStep == CreateTemplateStep.review;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (currentStep != CreateTemplateStep.basicInfo)
          OutlinedButton(
            onPressed: previousStep,
            child: const Text('Back'),
          ),
        ElevatedButton(
          onPressed: saving ? null : (isLastStep ? _saveTemplate : nextStep),
          child: saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isLastStep ? 'Save & Submit' : 'Next'),
        ),
      ],
    );
  }
}
