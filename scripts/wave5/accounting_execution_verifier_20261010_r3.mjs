// Pure verification algorithm extracted unchanged from the frozen evidence runner.
// No imports, process arguments, filesystem operations, or command-line entrypoint.
// Extraction only normalizes CRLF to LF; all function bodies are byte-for-byte equal.
export const verifierProvenance=Object.freeze([{"path":"scripts/wave5/run_accounting_checks_20261010_r2.mjs","sha256":"f80f73fde4a56717a28fce7cb2624a2b23590bbaa74f906a8fe07acc2427eaf0"},{"path":"scripts/wave5/record_continuation_windows.mjs","sha256":"2c3b2b93742d0e50546ff2ab7023f828616bf335ba845f99630f2fda5f6e13b3"}]);
const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(condition,message)=>{if(!condition)throw Error(message);};

export function parseTestLog(raw) {
  const text = raw.replace(/\x1b\[[0-9;]*m/g, '').replace(/\r/g, '');
  const summaries = [...text.matchAll(/^.*\+(\d+)((?:\s+[~-]\d+)*)\s*:\s*(All tests passed!|Some tests failed\.)\s*$/gm)];
  const summary = summaries.at(-1);
  if (!summary) return null;
  const errors = [...text.matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.*?)\s+\[E\]\s*$/gm)];
  let previousEnd = 0;
  const failures = errors.map(error => {
    const segment = text.slice(previousEnd, error.index);
    previousEnd = error.index + error[0].length;
    const goldens = [...segment.matchAll(/Golden "(goldens\/[^"\r\n]+\.png)":\s*Pixel\s+test\s+failed/g)];
    return { name: error[1], kind: goldens.length ? 'golden-comparison' : 'other', golden: goldens.at(-1)?.[1] ?? null };
  });
  return {
    passedTests: Number(summary[1]),
    failedTests: Number(summary[2].match(/-(\d+)/)?.[1] ?? 0),
    skippedTests: Number(summary[2].match(/~(\d+)/)?.[1] ?? 0),
    allTestsPassed: summary[3] === 'All tests passed!', failures,
  };
}

export function executedTests(text,workingDirectory,selectedFiles){
  const cwd=workingDirectory.replaceAll('\\','/').replace(/\/$/,'')+'/';
  const entries=[...text.replace(/\r/g,'').replace(/\x1b\[[0-9;]*m/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)];
  const identities=[];
  for(const m of entries){
    const actual=m[1].replaceAll('\\','/'),file=actual.startsWith(cwd)?actual.slice(cwd.length):actual;
    must(selectedFiles.includes(file),'EXECUTED_OUTSIDE_ACCOUNTING_SCOPE:'+actual);
    if(m[2]==='(setUpAll)'||m[2]==='(tearDownAll)')continue;
    identities.push(file+': '+m[2]);
  }
  return identities.sort();
}
export function verifyExecution(raw,workingDirectory,selectedFiles,exitCode){
  const text=raw.toString('utf8'),parsed=parseTestLog(text),identities=executedTests(text,workingDirectory,selectedFiles);
  const actualFiles=[...new Set(identities.map(id=>id.slice(0,id.indexOf(': '))))].sort();
  must(exitCode===0&&parsed?.allTestsPassed&&parsed.passedTests>0&&parsed.failedTests===0&&parsed.skippedTests===0,'ACCOUNTING_STAGE_NOT_GREEN');
  must(identities.length===parsed.passedTests&&new Set(identities).size===identities.length,'UNIQUE_ACCOUNTING_IDENTITIES_COUNT_REQUIRED');
  must(eq(actualFiles,[...selectedFiles].sort()),'EXACT_ACCOUNTING_TEST_FILE_COVERAGE_REQUIRED');
  return{parsed,identities,actualFiles,perFileCounts:actualFiles.map(file=>({file,passedTests:identities.filter(id=>id.startsWith(file+': ')).length}))};
}
