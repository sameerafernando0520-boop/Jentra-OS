// One-time namespace/exception adapter of the existing reviewed browser crypto
// store. The employee implementation and its persistent namespace stay intact.
import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const source=new URL('../../../apps/jentra_employee/lib/src/data/employee_storage_web.dart',import.meta.url);
const target=new URL('../../../packages/jentra_platform/lib/src/browser_protected_store.dart',import.meta.url);
let code=await readFile(source,'utf8');
assert.ok(code.includes('final class WebEmployeeKeyValueStore implements EmployeeKeyValueStore'));
code=code.replace("import 'employee_gateway.dart';\nimport 'employee_storage.dart';",`abstract interface class ProtectedBrowserStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class BrowserStorageFailure implements Exception {
  const BrowserStorageFailure(this.code, this.message);
  final String code, message;
}`);
code=code.replace(/EmployeeKeyValueStore createEmployeeKeyValueStore\(\{[\s\S]*?\}\) => WebEmployeeKeyValueStore\(projectUrl: projectUrl\);\n/,'');
code=code.replaceAll('WebEmployeeKeyValueStore','ProtectedBrowserKeyValueStore')
 .replaceAll('implements EmployeeKeyValueStore','implements ProtectedBrowserStore')
 .replaceAll('EmployeeFailure','BrowserStorageFailure')
 .replaceAll('jentra_employee_encrypted_v1_','jentra_os_encrypted_v1_')
 .replaceAll('jentra.employee.','jentra.desktop.')
 .replaceAll('The employee app','Jentra OS');
assert.ok(!code.includes("import 'employee_")&&!code.includes('EmployeeFailure')&&!code.includes('jentra.employee.'));
await writeFile(target,code,{flag:'wx'});
console.log('Protected browser store derived with a separate OS namespace; employee source unchanged.');
