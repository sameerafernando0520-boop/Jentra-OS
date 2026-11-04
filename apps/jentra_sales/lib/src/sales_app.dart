import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'sales_controller.dart';
import 'ui/components.dart';
import 'ui/login.dart';
import 'ui/workspace.dart';
import 'ui/field_sales_workspace.dart';

class SalesApp extends StatelessWidget {
  const SalesApp({required this.controller, super.key});
  final SalesController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'Jentra Sales',
      debugShowCheckedModeBanner: false,
      theme: salesTheme(Brightness.light),
      darkTheme: salesTheme(Brightness.dark),
      themeMode: controller.themeMode,
      supportedLocales: const [Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: controller.field?.isOpen == true
          ? FieldSalesWorkspace(controller.field!, onLeave: controller.leave)
          : controller.preview
          ? SalesWorkspace(controller)
          : SalesLogin(controller),
    ),
  );
}
