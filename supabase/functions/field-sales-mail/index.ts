import {createMailWorker} from '../../../workers/field-sales/mail_worker.mjs';

// Deploy only with its own scheduler secret and explicit organization policy.
// No public recipient/address parameter, automatic startup loop or default send.
Deno.serve(createMailWorker({env:Deno.env}));
