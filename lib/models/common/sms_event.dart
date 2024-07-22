import 'package:event_bus/event_bus.dart';

// Global instance of EventBus
EventBus eventBus = EventBus();

class SMSEvent {
  final String message;
  final bool success;

  SMSEvent(this.message, {this.success = true});
}
