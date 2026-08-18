import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/build_provenance.dart';

void main() {
  test('heartbeat refreshes when only the embedded commit changes', () {
    expect(
      merchantHeartbeatBuildChanged(
        lastVersion: '4.8.0',
        lastBuild: 88,
        lastCommit: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        currentVersion: '4.8.0',
        currentBuild: 88,
        currentCommit: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
      isTrue,
    );
  });

  test('heartbeat stays throttled for the same release artifact', () {
    expect(
      merchantHeartbeatBuildChanged(
        lastVersion: '4.8.0',
        lastBuild: 88,
        lastCommit: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        currentVersion: '4.8.0',
        currentBuild: 88,
        currentCommit: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      isFalse,
    );
  });

  test('local builds without provenance still compare version and build', () {
    expect(
      merchantHeartbeatBuildChanged(
        lastVersion: '4.8.0',
        lastBuild: 87,
        lastCommit: null,
        currentVersion: '4.8.0',
        currentBuild: 88,
        currentCommit: '',
      ),
      isTrue,
    );
  });
}
