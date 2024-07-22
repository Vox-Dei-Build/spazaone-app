import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:provider/provider.dart';
import 'package:pasella/constants/constants.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    this.label,
    required this.hintText,
    required this.prefixIcon,
    this.textInputType,
    this.suffixOptions,
    this.controller,
    this.inputFormat,
    this.textCapitalization,
    this.obscureText,
    this.onChanged,
    this.maxLength,
    this.focusNode,
    this.margin,
    this.validator,
    this.readOnly = false,
  });

  final String? label;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? textInputType;
  final Widget? suffixOptions;
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormat;
  final TextCapitalization? textCapitalization;
  final bool? obscureText;
  final Function(String)? onChanged;
  final int? maxLength;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry? margin;
  final String? Function(String?)? validator;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Consumer<AppModel>(
      builder: (context, value, child) {
        return Container(
          margin: margin ??
              EdgeInsets.only(bottom: SizeConfig.heightMultiplier * 0.5),
          padding: EdgeInsets.fromLTRB(
            SizeConfig.imageSizeMultiplier * 1.5,
            SizeConfig.imageSizeMultiplier * 1.5,
            SizeConfig.imageSizeMultiplier * 1.5,
            SizeConfig.heightMultiplier * 1.5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(
                  label!,
                  style: kLabelStyle.copyWith(
                      fontSize: SizeConfig.textMultiplier * 1.8),
                ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.5),
              TextFormField(
                controller: controller,
                validator: validator,
                focusNode: focusNode,
                onChanged: onChanged,
                maxLength: maxLength,
                obscureText: obscureText ?? false,
                obscuringCharacter: '●',
                textCapitalization:
                    textCapitalization ?? TextCapitalization.none,
                inputFormatters: inputFormat,
                keyboardType: textInputType,
                style: kTextFieldStyle.copyWith(
                    fontSize: SizeConfig.textMultiplier * 1.8),
                readOnly: readOnly,
                decoration: InputDecoration(
                  counterText: '',
                  prefixIconConstraints: BoxConstraints(
                    minWidth: SizeConfig.imageSizeMultiplier * 10,
                    minHeight: 0,
                  ),
                  suffixIconConstraints: BoxConstraints(
                    minWidth: SizeConfig.imageSizeMultiplier * 10,
                    minHeight: 0,
                  ),
                  contentPadding:
                      EdgeInsets.all(SizeConfig.imageSizeMultiplier * 1.5),
                  fillColor: kPrimaryColor,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: Color(0xff757784),
                    fontSize: SizeConfig.textMultiplier * 1.8,
                  ),
                  prefixIcon: Icon(
                    prefixIcon,
                    color: kPrimaryColor,
                    size: SizeConfig.imageSizeMultiplier * 6,
                  ),
                  suffix: suffixOptions,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
