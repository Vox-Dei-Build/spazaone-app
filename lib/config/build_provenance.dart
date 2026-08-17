class BuildProvenance {
  BuildProvenance._();

  static const commitSha = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: '',
  );

  static bool get hasCommitSha =>
      RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(commitSha);
}
