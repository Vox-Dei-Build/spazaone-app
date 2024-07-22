import 'package:flutter/material.dart';

class ServiceSelectionWidget extends StatelessWidget {
  final String selectedService;
  final List<String> services;
  final Function(String?) onChanged;

  const ServiceSelectionWidget({
    Key? key,
    required this.selectedService,
    required this.services,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedService,
      onChanged: onChanged,
      items: services.map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
      decoration: InputDecoration(
        labelText: 'Service',
        prefixIcon: Icon(Icons.business),
      ),
    );
  }
}
