import 'employee_photo.dart';
import 'employee_native_photo_factory.dart'
    if (dart.library.js_interop) 'employee_browser_photo.dart'
    as platform;

EmployeePhotoPicker createEmployeePhotoPicker() =>
    platform.createBrowserEmployeePhotoPicker();
