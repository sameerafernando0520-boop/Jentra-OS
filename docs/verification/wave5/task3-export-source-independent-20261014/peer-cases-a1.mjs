// This is an append-only controlled-test fragment for the preserved author
// suite. The review runner redirects only that suite's output base to this
// independent directory before appending these cases. No live ports are used.

test('peer: an already cancelled run saves its stop, dispatches nothing, and closes', async () => {
 const controller = new AbortController(); controller.abort();
 const s = await scenario({abortController: controller});
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'EXPORT_EXECUTION_ABORTED');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 0);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0);
  return true;
 });
 assert.equal(s.calls.length, 0); assert.equal(s.closed(), true);
 const saved = await readJson(path.join(s.directory, '99-stop.json'));
 assert.equal(saved.completed.length, 0); assert.equal(saved.lastOriginalCommand, null);
});

test('peer: cancellation after CSV persistence prevents the private intent and registration', async () => {
 const controller = new AbortController(), s = await scenario({abortController: controller});
 const save = s.ports.writeFile;
 s.ports.writeFile = async (...args) => { const receipt = await save(...args); controller.abort(); return receipt; };
 await assert.rejects(s.run());
 assert.equal(s.calls.length, 15); assert.equal(s.registrations.length, 0);
 assert.equal(s.journal.some(row => row.private), false); assert.equal(s.closed(), true);
 const saved = await readJson(path.join(s.directory, '99-stop.json'));
 assert.equal(saved.actualReadOnlyResolutionAttempts, 0); assert.equal(saved.lastOriginalCommand, null);
});

test('peer: a stale pre-registration server clock is saved before rejection and never resolved as a sent command', async () => {
 const s = await scenario(), read = s.ports.management;
 s.ports.management = async query => {
  const value = await read(query);
  if (query === REMAINING_ACTIVITY_SQL) { value.value[0].observation.observedAt = '2026-10-14T06:59:14.999Z'; return response(value.value); }
  return value;
 };
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'FRESH_EXPORT_SERVER_CLOCK_REQUIRED');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 16);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0);
  assert.equal(error.exportStop.lastOriginalCommand.writeAttempted, false);
  return true;
 });
 assert.equal(s.registrations.length, 0); assert.equal(s.closed(), true);
 const evidence = s.journal.find(row => row.file?.startsWith('quiescence-'));
 assert.equal(evidence.persistedBeforeValidation, true);
 assert.equal(evidence.value.rows[0].observation.observedAt, '2026-10-14T06:59:14.999Z');
});

test('peer: failed stop persistence is explicitly unavailable and still closes', async () => {
 const s = await scenario({failOrdinal: 1, failPersist: file => file === '99-stop.json'});
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'EXPORT_STOP_EVIDENCE_UNAVAILABLE');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 1); return true;
 });
 assert.equal(s.calls.length, 1); assert.equal(s.closed(), true);
 await assert.rejects(fs.readFile(path.join(s.directory, '99-stop.json')), {code: 'ENOENT'});
});

test('peer: a constructed MFA claim or foreign factor stops before any preview', async () => {
 for (const changeProof of [proof => { proof.constructedAalClaims = true; }, proof => { proof.factorId = writerId; }]) {
  const s = await scenario({changeProof}); await assert.rejects(s.run(), /GENUINE_INDEPENDENT_EXPORT_MFA_SESSIONS_REQUIRED/);
  assert.equal(s.calls.length, 14); assert.equal(s.registrations.length, 0); assert.equal(s.closed(), true);
 }
});

test('peer: tampered statement disk bytes preserve the confirmed pipeline and prevent the second registration', async () => {
 const s = await scenario(), read = s.ports.readFile;
 s.ports.readFile = async file => { const bytes = await read(file); return file.includes('statement') ? Buffer.concat([bytes, Buffer.from('\nchanged')]) : bytes; };
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'ACTUAL_SAVED_EXPORT_BYTES_REQUIRED');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 20);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0);
  assert.equal(error.exportStop.completed.length, 1); return true;
 });
 assert.equal(s.registrations.length, 1); assert.equal(s.registrations[0].p_command_id, EXPORTS_COMMANDS[0].commandId);
 assert.equal(s.closed(), true);
});

test('peer: an extra date mutation fails final reconciliation without replaying either confirmed export', async () => {
 const s = await scenario({changeState: (value, after) => { if (after) value.wholeSource.dateProposals = 4; }});
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'EXACT_UNCHANGED_EXPORT_FINANCE_COUNTS_REQUIRED');
  assert.equal(error.exportStop.completed.length, 2); assert.equal(error.exportStop.actualOrdinaryAttempts, 24);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0); return true;
 });
 assert.equal(s.registrations.length, 2); assert.equal(new Set(s.registrations.map(row => row.p_command_id)).size, 2);
 assert.equal(s.closed(), true);
});

test('peer: the original authority expiry reserves both request windows even with a later run deadline', async () => {
 const expiry = Date.parse(EXPORTS_RUNTIME_EXPIRY), clock = expiry - 89999;
 const gate = createExportsCallGate({now: () => clock, startedAt: clock, expiresAt: EXPORTS_RUNTIME_EXPIRY});
 let sends = 0;
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0], async () => { sends++; }), /EXPORT_INFLIGHT_AND_RESOLUTION_TIME_RESERVED_REQUIRED/);
 assert.equal(sends, 0); assert.equal(gate.snapshot().actualOrdinaryAttempts, 0);
});

for (const [boundary, elapsed] of [['run', 900000], ['owner scope', 90000]]) {
 test(`peer: a request failure at the exact ${boundary} deadline still saves a local stop without late requests`, async () => {
  let clock = now(); const originalStart = clock, s = await scenario(), read = s.ports.management;
  s.ports.management = async query => {
   await read(query); clock = originalStart + elapsed;
   const error = Error('controlled deadline-bound failure'); error.publicCode = 'CONTROLLED_AT_EXECUTION_END'; throw error;
  };
  const options = {now: () => clock, startedAt: originalStart,
   ...(boundary === 'owner scope' ? {expiresAt: new Date(originalStart + elapsed).toISOString()} : {})};
  await assert.rejects(s.run(options), error => {
   assert.equal(error.publicCode, 'CONTROLLED_AT_EXECUTION_END');
   assert.equal(error.exportStop.actualOrdinaryAttempts, 1); assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0); return true;
  });
  assert.equal(s.calls.length, 1); assert.equal(s.closed(), true);
  const stop = await readJson(path.join(s.directory, '99-stop.json'));
  assert.equal(stop.failureCode, 'CONTROLLED_AT_EXECUTION_END'); assert.equal(stop.lastOriginalCommand, null);
 });
}
