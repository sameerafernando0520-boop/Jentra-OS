import 'package:flutter/material.dart';

import '../../../../core/constants/app_module.dart';
import '../../../../core/widgets/module_placeholder_screen.dart';

final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ModulePlaceholderScreen(module: AppModule.settings);
}
