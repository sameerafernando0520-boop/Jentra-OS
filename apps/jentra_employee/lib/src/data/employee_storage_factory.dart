import 'employee_storage.dart';
import 'employee_storage_native_factory.dart'
    if (dart.library.js_interop) 'employee_storage_web.dart'
    as platform;

/// Create once and share with auth, PKCE, commands, drafts and photos.
EmployeeKeyValueStore createEmployeeKeyValueStore({
  required String projectUrl,
}) => platform.createEmployeeKeyValueStore(projectUrl: projectUrl);
