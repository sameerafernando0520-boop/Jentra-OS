The isolated Windows setup is already included in the approved runtime bundle. Fresh read-only validation passed on 13 October at 16:37 Sri Lanka time: all 1068 source inputs, all 34 Connected release files, the exact executable identity and absence of the target account/package were verified. The current Windows token is not an administrator.

Right-click [Jentra OS Isolated Windows Setup](<../../../dist/Jentra OS Isolated Windows Setup 20261013 r5.cmd>) and choose **Run as administrator**. Handle UAC yourself. Enter a new password only in its two hidden prompts. The helper creates only the standard account `jentra-w5-runtime` and copies the verified Connected release to `C:\Users\Public\Documents\JentraWave5Runtime\20261009`, with read-and-execute access for that account. It preserves existing accounts, Windows sessions and app stores. It does not save or print the password, sign in, launch the app or claim native acceptance.

If setup stops, report only its failure code; keep partial state for investigation. Do not rerun or delete the account/package. Keep all passwords and MFA codes out of chat.

After a successful setup, keep existing sessions signed in. Windows must initialize the new profile through a private human sign-in. Connected app login, native keyboard and accounting workflow evidence remain separate checks.

The Computer Use skill's [guidance](<C:/Users/sheha/.codex/plugins/cache/openai-bundled/computer-use/26.1007.21434/docs/guidance.md>) says “Do not automate user authentication dialogs” and “Do not act on security or privacy permission requests.” This is why the UAC and private login steps require the human. The [skill entrypoint](<C:/Users/sheha/.codex/plugins/cache/openai-bundled/computer-use/26.1007.21434/skills/computer-use/SKILL.md>) requires reading that guidance. No additional runtime approval is being requested.

Actual proof: [fresh validation](native-profile-helper-validation-20261013-r5-a2.json). The earlier failed account-lookup attempt is retained separately.
