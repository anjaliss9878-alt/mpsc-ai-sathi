import 'package:flutter/widgets.dart';

/// No-op on VM/mobile. Web implementation syncs the HTML editing overlay.
class WebTopicEditingSync {
  void attach(TextEditingController controller, FocusNode focusNode) {}

  void detach() {}

  void pull(TextEditingController controller) {}
}
