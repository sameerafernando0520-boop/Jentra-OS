import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../l10n/employee_strings.dart';
import 'employee_components.dart';

class EmployeeSettingsScreen extends StatelessWidget {
  const EmployeeSettingsScreen({
    required this.themeMode,
    required this.locale,
    required this.onChanged,
    super.key,
  });
  final ThemeMode themeMode;
  final Locale locale;
  final void Function(ThemeMode theme, Locale locale) onChanged;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s('settings'))),
      body: EmployeePageBody(
        children: [
          EmployeeHeading(s('language')),
          JentraPanel(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('employee-language'),
                isExpanded: true,
                value: Localizations.localeOf(context).languageCode,
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'si', child: Text('සිංහල')),
                  DropdownMenuItem(value: 'ta', child: Text('தமிழ்')),
                ],
                onChanged: (value) {
                  if (value != null) onChanged(themeMode, Locale(value));
                },
              ),
            ),
          ),
          EmployeeHeading(s('appearance')),
          JentraPanel(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ThemeMode>(
                key: const Key('employee-appearance'),
                isExpanded: true,
                value: themeMode,
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(s('system')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(s('light')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(s('dark')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(value, Localizations.localeOf(context));
                  }
                },
              ),
            ),
          ),
          EmployeeMessage(
            title: s('security'),
            message: s('securityCopy'),
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }
}
