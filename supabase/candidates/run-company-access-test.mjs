// Local-only rollback candidate runner. Never resolves a linked/hosted target.
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {stageAndRun} from './run-employee-push-test.mjs';

const name='20261028130000_company_access_administration.sql';
export function buildSuite(candidate,harness){
 const controls=[...harness.matchAll(/^[\t ]*(begin|commit|rollback)\s*;/gim)].map(m=>m[1].toLowerCase());
 if(!/^(?:\s|--[^\r\n]*(?:\r?\n|$))*begin;[\t ]*(?:\r?\n|$)/i.test(harness)||
  !/rollback;\s*$/i.test(harness)||controls.join(',')!=='begin,rollback')throw Error('Rollback harness required.');
 const include=new RegExp(`^\\\\ir \\.\\.\\/${name.replaceAll('.','\\.')}[\\t ]*\\r?$`,'m');
 if(typeof candidate!=='string'||harness.split(include).length!==2||/^\s*(?:begin|commit|rollback)\s*;/im.test(candidate))throw Error('Candidate/include mismatch.');
 const result=harness.replace(include,()=>`-- Exact company administration candidate, rollback only.\n${candidate}`);
 if(/^\s*\\(?:i|ir|include|include_relative)\s/m.test(result))throw Error('Unresolved include.');
 return result;
}
export async function main(args){
 if(args.length!==1||!['--check','--run-local'].includes(args[0]))throw Error('Use --check or --run-local only; hosted/linked targets are forbidden.');
 const [candidate,harness]=await Promise.all([readFile(new URL(name,import.meta.url),'utf8'),
  readFile(new URL('tests/company_access_administration_test.sql',import.meta.url),'utf8')]);
 const suite=buildSuite(candidate,harness);
 if(args[0]==='--check'){console.log('Company/access suite is self-contained. PostgreSQL has not been executed.');return 0;}
 const root=fileURLToPath(new URL('../../',import.meta.url));
 return stageAndRun({suite,testsDir:join(root,'supabase','candidates'),cwd:root});
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 main(process.argv.slice(2)).then(code=>{process.exitCode=code;}).catch(()=>{
  console.error('Company/access rollback suite could not complete. Check the isolated local stack and inputs.');process.exitCode=1;
 });
}
