import {readFile} from 'node:fs/promises';
const file=process.argv[3]==='bootstrap'?'runtime-bootstrap-probe-20261008.sql':'runtime-candidate-20261008.sql';
const sql=await readFile(new URL('../../docs/verification/wave5/'+file,import.meta.url),'utf8');
const part=Number(process.argv[2]);
if(!Number.isInteger(part)||part<0||part>30)throw Error('PART_INVALID');
process.stdout.write(sql.slice(part*120000,(part+1)*120000));
