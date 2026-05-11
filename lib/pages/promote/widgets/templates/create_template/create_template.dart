import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/force_boilerplate.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/basic_info_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/content_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/review_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/template_submitted_success_page.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/wizard_stepper.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

enum CreateTemplateStep {
  basicInfo,
  content,
  review,
}

/// Bundle of fields used to prefill [CreateTemplatePage] when the user is
/// fixing-and-resubmitting a rejected template, or retrying a failed
/// submission. The wizard treats this exactly like a fresh submission — a new
/// document is created — but the friction of retyping is removed.
class TemplatePrefill {
  final String displayName;
  final String whatsappContent;
  final String smsContent;
  final String mediaUrl;
  final bool includeWhatsApp;
  final bool includeSMS;

  /// Optional reason from the previous rejection, surfaced as a banner so the
  /// merchant can address it before resubmitting.
  final String? rejectionReason;

  const TemplatePrefill({
    this.displayName = '',
    this.whatsappContent = '',
    this.smsContent = '',
    this.mediaUrl = '',
    this.includeWhatsApp = true,
    this.includeSMS = true,
    this.rejectionReason,
  });
}

class CreateTemplatePage extends StatefulWidget {
  final PromotionsViewModel viewModel;
  final TemplatePrefill? prefill;

  const CreateTemplatePage({
    super.key,
    required this.viewModel,
    this.prefill,
  });

  @override
  State<CreateTemplatePage> createState() => _CreateTemplatePageState();
}

class _CreateTemplatePageState extends State<CreateTemplatePage> {
  final _formKey = GlobalKey<FormState>();
  final _templateNameController = TextEditingController();
  final _whatsappContentController = TextEditingController();
  final _smsContentController = TextEditingController();
  final _mediaUrlController = TextEditingController();

  // Live state from BasicInfoStep so we can gate Next correctly.
  String _sanitizedName = '';
  bool _nameIsDuplicate = false;

  CreateTemplateStep currentStep = CreateTemplateStep.basicInfo;
  bool includeWhatsApp = true;
  bool includeSMS = true;
  bool saving = false;

  DynamicPricingService? _pricingService;
  double? _whatsappPrice;
  double? _smsPricePerSegment;
  int _smsSegments = 1;
  SmsEncodingInfo _smsEncodingInfo = const SmsEncodingInfo(
    encoding: SmsEncoding.gsm7,
    septetLength: 0,
    offendingCharacters: <String>{},
  );
  final PhotoUploadUtil _photoUtil = PhotoUploadUtil();
  bool uploadingImage = false;
  PromotionsViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();

    // Apply prefill from a "fix & resubmit" or retry flow before first paint.
    final pre = widget.prefill;
    if (pre != null) {
      _templateNameController.text = pre.displayName;
      _whatsappContentController.text = pre.whatsappContent;
      _smsContentController.text = pre.smsContent;
      _mediaUrlController.text = pre.mediaUrl;
      includeWhatsApp = pre.includeWhatsApp;
      includeSMS = pre.includeSMS;
      _smsSegments = SMSPricingUtil.calculateSegments(pre.smsContent);
      _smsEncodingInfo = SMSPricingUtil.classify(pre.smsContent.trim());
    }

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

    // STEP 1: Basic Info — inline validation; just block if form invalid.
    if (currentStep == CreateTemplateStep.basicInfo) {
      if (!isFormValid) return;
    }

    // STEP 2: Content → require non-empty body for each chosen channel
    if (currentStep == CreateTemplateStep.content) {
      if (_whatsappContentController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message body is required.')),
        );
        return;
      }
    }

    setState(() {
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
      _smsEncodingInfo = SMSPricingUtil.classify(text.trim());
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
      'displayName': _templateNameController.text.trim(),
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
        // Replace the wizard with a "what happens next" success screen,
        // then pop both back to wherever the wizard was launched from.
        // Returns `true` to the original caller so it can refresh.
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TemplateSubmittedSuccessPage(
              displayName: _templateNameController.text.trim().isEmpty
                  ? (_sanitizedName.isEmpty
                      ? 'your template'
                      : _sanitizedName)
                  : _templateNameController.text.trim(),
              onDone: () => Navigator.of(context).pop(true),
              onViewPending: () => Navigator.of(context).pop(true),
            ),
          ),
        );
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
              if (widget.prefill?.rejectionReason != null)
                _RejectionReasonBanner(
                    reason: widget.prefill!.rejectionReason!),
              WizardStepper(
                steps: const ['Name', 'Content', 'Review'],
                currentIndex: currentStep.index,
              ),
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
          displayNameController: _templateNameController,
          sanitize: _sanitizeTemplateName,
          userId: FirebaseAuth.instance.currentUser?.uid ?? '',
          onSanitizedChanged: (sanitized, isDuplicate) {
            setState(() {
              _sanitizedName = sanitized;
              _nameIsDuplicate = isDuplicate;
            });
          },
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
          smsEncodingInfo: _smsEncodingInfo,
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
          smsEncodingInfo: _smsEncodingInfo,
          shopName: viewModel.shopName,
        );
    }
  }

  // 1) Remove any calls to validate() in build:
  Widget _buildNavigationButtons() {
    final isLast = currentStep == CreateTemplateStep.review;
    final nameValid = _sanitizedName.isNotEmpty && !_nameIsDuplicate;

    final whatsappFilled = _whatsappContentController.text.trim().isNotEmpty;
    final smsFilled = _smsContentController.text.trim().isNotEmpty;
    final contentValid =
        (!includeWhatsApp || whatsappFilled) && (!includeSMS || smsFilled);

    final canProceed = currentStep == CreateTemplateStep.basicInfo
        ? nameValid
        : currentStep == CreateTemplateStep.content
            ? contentValid
            : true;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (currentStep != CreateTemplateStep.basicInfo)
          OutlinedButton(onPressed: previousStep, child: const Text('Back'))
        else
          const SizedBox.shrink(),
        ElevatedButton(
          onPressed: saving || !canProceed
              ? null
              : () {
                  if (currentStep == CreateTemplateStep.basicInfo) {
                    if (!_formKey.currentState!.validate()) return;
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

class _RejectionReasonBanner extends StatelessWidget {
  final String reason;
  const _RejectionReasonBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WhatsApp rejected the previous version',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reason: $reason',
                  style: const TextStyle(color: Colors.red, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tweak the wording or media to address the issue, then resubmit.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
