// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_file_pick_support.dart';

/// Flutter web paints a full-screen semantics overlay. Clicks on
/// [OutlinedButton] often only focus that overlay node, so
/// `FilePicker.platform.pickFiles` never runs and no `<input type="file">`
/// is created.
///
/// This control keeps the same visible button, and places a real HTML file
/// input on `document.body` (above the overlay) over the button's screen
/// rect so the browser file chooser opens from a trusted click.
///
/// Uses the same `dart:html` web path as the Admin PDF iframe fallback.
class AdminFilePickButton extends StatefulWidget {
  const AdminFilePickButton({
    super.key,
    required this.label,
    required this.icon,
    required this.allowedExtensions,
    required this.onPicked,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final List<String> allowedExtensions;
  final ValueChanged<AdminPickedLocalFile> onPicked;
  final bool enabled;

  @override
  State<AdminFilePickButton> createState() => _AdminFilePickButtonState();
}

class _AdminFilePickButtonState extends State<AdminFilePickButton>
    with WidgetsBindingObserver {
  final GlobalKey _key = GlobalKey();
  html.FileUploadInputElement? _input;
  StreamSubscription<html.Event>? _changeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  @override
  void didUpdateWidget(covariant AdminFilePickButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allowedExtensions != widget.allowedExtensions ||
        oldWidget.label != widget.label) {
      _input?.accept = adminFileInputAccept(widget.allowedExtensions);
      _input?.title = widget.label;
      _input?.setAttribute('aria-label', widget.label);
    }
    _syncOverlay();
  }

  @override
  void didChangeMetrics() {
    _syncOverlay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changeSub?.cancel();
    _input?.remove();
    _input = null;
    super.dispose();
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    _syncOverlay();
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  html.FileUploadInputElement _ensureInput() {
    final existing = _input;
    if (existing != null) return existing;
    final input = html.FileUploadInputElement()
      ..accept = adminFileInputAccept(widget.allowedExtensions)
      ..multiple = false
      ..title = widget.label
      ..style.position = 'fixed'
      ..style.zIndex = '2147483646'
      ..style.opacity = '0'
      ..style.cursor = 'pointer'
      ..style.margin = '0'
      ..style.padding = '0'
      ..style.border = '0'
      ..style.overflow = 'hidden';
    input.setAttribute('aria-label', widget.label);
    _changeSub = input.onChange.listen((_) => _onNativeChange(input));
    html.document.body!.append(input);
    _input = input;
    return input;
  }

  void _onNativeChange(html.FileUploadInputElement input) {
    final files = input.files;
    if (files == null || files.isEmpty) return;
    final file = files.first;
    if (!adminFileNameMatchesExtensions(file.name, widget.allowedExtensions)) {
      input.value = '';
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      final Uint8List bytes;
      if (result is Uint8List) {
        bytes = result;
      } else if (result is ByteBuffer) {
        bytes = Uint8List.view(result);
      } else {
        input.value = '';
        return;
      }
      if (bytes.isEmpty) {
        input.value = '';
        return;
      }
      widget.onPicked(AdminPickedLocalFile(name: file.name, bytes: bytes));
      input.value = '';
    });
    reader.readAsArrayBuffer(file);
  }

  void _syncOverlay() {
    final input = widget.enabled ? _ensureInput() : _input;
    if (input == null) return;
    if (!widget.enabled) {
      input.style.display = 'none';
      input.style.pointerEvents = 'none';
      return;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      input.style.display = 'none';
      input.style.pointerEvents = 'none';
      return;
    }
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    if (size.width < 8 || size.height < 8) {
      input.style.display = 'none';
      input.style.pointerEvents = 'none';
      return;
    }
    input.style.display = 'block';
    input.style.pointerEvents = 'auto';
    input.style.left = '${offset.dx}px';
    input.style.top = '${offset.dy}px';
    input.style.width = '${size.width}px';
    input.style.height = '${size.height}px';
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: widget.enabled,
          child: OutlinedButton.icon(
            onPressed: widget.enabled ? () {} : null,
            icon: Icon(widget.icon),
            label: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
