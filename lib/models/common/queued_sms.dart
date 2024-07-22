import 'package:hive_local_storage/hive_local_storage.dart';

@HiveType(typeId: 0)
class QueuedSMS extends HiveObject {
  @HiveField(0)
  final String phoneNumber;

  @HiveField(1)
  final String message;

  @HiveField(2)
  final String currentUserId;

  @HiveField(3)
  final String customerId;

  @HiveField(4)
  final String customerName;

  @HiveField(5)
  final double? amount;

  QueuedSMS(
      {required this.phoneNumber,
      required this.message,
      required this.currentUserId,
      required this.customerId,
      required this.customerName,
      this.amount});
}

class QueuedSMSAdapter extends TypeAdapter<QueuedSMS> {
  @override
  final int typeId = 0;

  @override
  QueuedSMS read(BinaryReader reader) {
    // Ensure the order matches the write method
    final phoneNumber = reader.readString();
    final message = reader.readString();
    final currentUserId = reader.readString();
    final customerId = reader.readString();
    final customerName = reader.readString();
    final amount = reader.readDouble();

    return QueuedSMS(
        phoneNumber: phoneNumber,
        message: message,
        currentUserId: currentUserId,
        customerId: customerId,
        customerName: customerName,
        amount: amount);
  }

  @override
  void write(BinaryWriter writer, QueuedSMS obj) {
    writer.writeString(obj.phoneNumber);
    writer.writeString(obj.message);
    writer.writeString(obj.currentUserId);
    writer.writeString(obj.customerId);
    writer.writeString(obj.customerName);
    bool hasAmount = obj.amount != null;
    writer.writeBool(hasAmount);
    if (hasAmount) {
      writer.writeDouble(
          obj.amount!); // Use '!' to assert non-null as we checked already
    }
  }
}
