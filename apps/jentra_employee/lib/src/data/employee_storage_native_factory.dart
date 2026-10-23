import 'employee_storage.dart';

EmployeeKeyValueStore createEmployeeKeyValueStore({
  required String projectUrl,
}) => NativeEmployeeKeyValueStore();
