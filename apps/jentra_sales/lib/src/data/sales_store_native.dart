import 'sales_store.dart';

SalesKeyValueStore createSalesKeyValueStore({required String projectUrl}) =>
    NativeSalesKeyValueStore();
