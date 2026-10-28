import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/data/employee_storage_factory.dart';

void main() {
  test(
    'VM factory retains the existing native protected storage implementation',
    () {
      expect(
        createEmployeeKeyValueStore(projectUrl: 'https://storage.example.test'),
        isA<NativeEmployeeKeyValueStore>(),
      );
    },
  );
}
