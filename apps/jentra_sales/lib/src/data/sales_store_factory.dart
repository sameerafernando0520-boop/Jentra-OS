import 'sales_store.dart';
import 'sales_store_native.dart'
    if (dart.library.js_interop) 'sales_store_web.dart'
    as platform;

SalesKeyValueStore createSalesStore({required String projectUrl}) =>
    platform.createSalesKeyValueStore(projectUrl: projectUrl);
