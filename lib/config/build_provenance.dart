class BuildProvenance {
  BuildProvenance._();

  static const commitSha = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: '',
  );

  static bool get hasCommitSha =>
      RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(commitSha);
}

bool merchantHeartbeatBuildChanged({
  required String? lastVersion,
  required int? lastBuild,
  required String? lastCommit,
  required String currentVersion,
  required int currentBuild,
  required String currentCommit,
}) {
  final normalizedCommit = currentCommit.toLowerCase();
  return lastVersion != currentVersion ||
      lastBuild != currentBuild ||
      (normalizedCommit.isNotEmpty && lastCommit != normalizedCommit);
}
