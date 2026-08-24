import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasella/utils/permission_helper.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('camera permission outcomes distinguish denial and app settings', () {
    expect(
      PermissionHelper.outcomeForStatus(PermissionStatus.granted),
      PermissionRequestOutcome.granted,
    );
    expect(
      PermissionHelper.outcomeForStatus(PermissionStatus.denied),
      PermissionRequestOutcome.denied,
    );
    expect(
      PermissionHelper.outcomeForStatus(PermissionStatus.permanentlyDenied),
      PermissionRequestOutcome.permanentlyDenied,
    );
    expect(
      PermissionHelper.outcomeForStatus(PermissionStatus.restricted),
      PermissionRequestOutcome.restricted,
    );
  });

  test('photo rationales match the selected photo purpose', () {
    expect(
      PermissionHelper.cameraRationaleMessage(
        PhotoPermissionPurpose.customer,
      ),
      contains('customer profile'),
    );
    expect(
      PermissionHelper.cameraRationaleMessage(
        PhotoPermissionPurpose.product,
      ),
      contains('product'),
    );
    expect(
      PermissionHelper.cameraRationaleMessage(
        PhotoPermissionPurpose.stockInvoice,
      ),
      contains('stock invoice'),
    );
  });

  test('camera failures provide an actionable gallery fallback', () {
    expect(
      PhotoUploadUtil.pickerFailureMessage(
        ImageSource.camera,
        'camera_not_available',
      ),
      allOf(contains('camera app'), contains('Gallery')),
    );
    expect(
      PhotoUploadUtil.pickerFailureMessage(
        ImageSource.gallery,
        'photo_access_denied',
      ),
      contains('photo access'),
    );
  });

  test('image compression strips EXIF metadata', () {
    expect(PhotoUploadUtil.preserveExifOnCompression, isFalse);
  });
}
