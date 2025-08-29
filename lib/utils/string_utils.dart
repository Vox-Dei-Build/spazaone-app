extension StringCasingExtension on String {
  String toTitleCase() {
    if (isEmpty) return this;
    return split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

String formatStringToCamelCase(String fullName) {
  // Trim white spaces and split the name into words
  List<String> words = fullName.trim().split(RegExp(r'\s+'));

  // Capitalize the first letter of each word and join them back
  String formattedName = words.map((word) {
    // Check if the word is not empty to avoid errors
    if (word.isNotEmpty) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }
    return word;
  }).join(' ');

  return formattedName;
}
