import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';

abstract interface class PayrollFiles {
  Future<String?> chooseExport();
  Future<void> write(String path, Uint8List bytes);
}

final class NativePayrollFiles implements PayrollFiles {
  const NativePayrollFiles();
  @override
  Future<String?> chooseExport() async => (await getSaveLocation(
    suggestedName: 'synthetic-payslip.json',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Synthetic payslip', extensions: ['json']),
    ],
  ))?.path;
  @override
  Future<void> write(String path, Uint8List bytes) =>
      XFile.fromData(bytes, mimeType: 'application/json').saveTo(path);
}
