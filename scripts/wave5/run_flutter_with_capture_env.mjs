// Windows/.NET can retain deleted environment variables as empty strings.
// Omit only unset capture destinations so optional test captures remain optional.
import {spawn} from 'node:child_process';
const [executable,...args]=process.argv.slice(2);
if(!executable)throw Error('FLUTTER_EXECUTABLE_REQUIRED');
const env={...process.env};
for(const name of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR']){
  if(!env[name])delete env[name];
}
const child=spawn(executable,args,{env,stdio:'inherit',windowsHide:true});
child.once('error',()=>{process.stderr.write('Flutter child could not start.\n');process.exitCode=1;});
child.once('exit',(code)=>{process.exitCode=code??1;});
