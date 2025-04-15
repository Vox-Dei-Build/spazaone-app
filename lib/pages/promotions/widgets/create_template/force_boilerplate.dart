String forceBoilerplate(String content) {
  // Remove any leading/trailing boilerplate if manually typed
  String stripped = content
      .replaceAll(
          RegExp(r'^Hi\s+{{customerName}}\s*[\n]*', caseSensitive: false), '')
      .replaceAll(RegExp(r'From\s+{{shopName}}\s*$', caseSensitive: false), '');

  return 'Hi {{customerName}},\n$stripped\nFrom {{shopName}}';
}
