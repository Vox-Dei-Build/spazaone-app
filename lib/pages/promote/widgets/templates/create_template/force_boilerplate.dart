String forceBoilerplate(String content) {
  // Remove existing boilerplate variants the user may have typed
  String stripped = content
      // Remove a leading greeting with customer placeholder
      .replaceAll(
          RegExp(r'^(Hi|Hello)\s+{{customerName}}\s*,?\s*[\n]*',
              caseSensitive: false),
          '')
      // Remove any trailing signature containing shopName
      .replaceAll(
          RegExp(r'(From|Regards|Kind regards|Thanks|Thank you|Warm regards)\s*,?\s*[\n]*({{shopName}}(\s+(team|Team))?)\s*[\.!\u2013\u2014-]*\s*$',
              caseSensitive: false),
          '')
      // Remove leading signature if user typed it at the top
      .replaceAll(
          RegExp(r'^(From|Regards|Kind regards|Thanks|Thank you|Warm regards)\s*,?\s*[\n]*{{shopName}}(\s+(team|Team))?\s*[:\-\u2013\u2014]?\s*[\n]*',
              caseSensitive: false),
          '');

  // Friendly greeting + safe sign-off that doesn't end with a variable
  // Ends with the static word "team" to avoid WA trailing-variable issues
  return 'Hello {{customerName}},\n$stripped\nKind regards,\nThe {{shopName}} team'.trim();
}
