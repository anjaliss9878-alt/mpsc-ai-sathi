import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_select_field.dart';
import 'package:mpsc_combine_ai/data/student_onboarding.dart';

/// Target-exam picker that commits via [MenuItemButton] so Flutter web
/// can select an exam (native [DropdownButtonFormField] often never fires).
class TargetExamSelectField extends StatelessWidget {
  const TargetExamSelectField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.requiredField = true,
    this.label = 'लक्ष्य परीक्षा (Target Exam)',
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool requiredField;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: requiredField
          ? (_) => (value == null || value!.isEmpty)
              ? 'लक्ष्य परीक्षा निवडा'
              : null
          : null,
      builder: (state) {
        final errorColor = Theme.of(context).colorScheme.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminSelectField(
              label: label,
              value: value ?? '',
              enabled: enabled,
              items: [
                for (final exam in targetExamOptions)
                  AdminSelectItem(id: exam, label: exam),
              ],
              onChanged: (id) {
                onChanged(id);
                state.didChange(id);
              },
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  state.errorText!,
                  style: TextStyle(color: errorColor, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}
