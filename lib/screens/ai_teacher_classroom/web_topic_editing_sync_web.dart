import 'dart:html' as html;

import 'package:flutter/widgets.dart';

/// Flutter web can show typed text in a DOM overlay (editing host or
/// semantics textarea) without updating [TextEditingController]. Capture
/// those input events and write them into the controller immediately.
class WebTopicEditingSync {
  TextEditingController? _controller;
  html.EventListener? _docListener;
  String _lastOverlayText = '';

  void attach(TextEditingController controller, FocusNode focusNode) {
    detach();
    _controller = controller;
    _lastOverlayText = controller.text;
    _docListener = (html.Event event) {
      final target = event.target;
      String? value;
      if (target is html.TextAreaElement) {
        value = target.value;
      } else if (target is html.InputElement) {
        value = target.value;
      }
      if (value == null) return;
      _apply(controller, value);
    };
    html.document.addEventListener('input', _docListener, true);
    html.document.addEventListener('change', _docListener, true);
    html.document.addEventListener('keyup', _docListener, true);
    html.document.addEventListener('compositionend', _docListener, true);
  }

  void detach() {
    final listener = _docListener;
    if (listener != null) {
      html.document.removeEventListener('input', listener, true);
      html.document.removeEventListener('change', listener, true);
      html.document.removeEventListener('keyup', listener, true);
      html.document.removeEventListener('compositionend', listener, true);
    }
    _docListener = null;
    _controller = null;
    _lastOverlayText = '';
  }

  void pull(TextEditingController controller) {
    final live = _overlayText();
    if (live != null && live.isNotEmpty) {
      _apply(controller, live);
      return;
    }
    if (_lastOverlayText.isNotEmpty) {
      _apply(controller, _lastOverlayText);
    }
  }

  void _apply(TextEditingController controller, String value) {
    _lastOverlayText = value;
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String? _overlayText() {
    final active = html.document.activeElement;
    if (active is html.TextAreaElement) return active.value;
    if (active is html.InputElement) return active.value;
    final host = html.document.querySelector('flt-text-editing-host textarea') ??
        html.document.querySelector('flt-semantics textarea') ??
        html.document.querySelector('textarea');
    if (host is html.TextAreaElement) return host.value;
    if (host is html.InputElement) return host.value;
    return null;
  }
}
