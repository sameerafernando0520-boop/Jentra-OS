import 'package:file_selector/file_selector.dart';

Future<FileSaveLocation?> jentraSaveLocation({
  required String suggestedName,
  required List<XTypeGroup> acceptedTypeGroups,
}) => getSaveLocation(
  suggestedName: suggestedName,
  acceptedTypeGroups: acceptedTypeGroups,
);
