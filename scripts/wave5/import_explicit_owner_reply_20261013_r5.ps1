param([switch]$ValidateOnly)

# Read only the exact credential reply in this current chat, after the human's
# direct instruction to use it. The credential never appears in a command,
# source file, environment variable, build, stdout or public evidence.
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskTranscript = 'C:\Users\sheha\.codex\sessions\2026\10\09\rollout-2026-10-09T23-46-29-01a121e1-81f0-76c1-8060-699f36ec225e.jsonl'
$taskCredentialQuestion = '["request_user_input_async","call_85e76c1e42c0441bae47f7f63607cc43",0]'
$taskReuseQuestion = '["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]'
$taskReuseText = 'Please use this. New ones cannot be generated repeatedly. This will expire in another 7 days; therefore, please use it for all tasks and complete this project.'
$taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5.json'
$taskSecret = $null
$taskPlain = $null
$taskReader = $null
$taskPhase = 'approval-validation'

function Write-TaskNewFile([string]$TaskPath, [string]$TaskText) {
    $taskBytes = [Text.UTF8Encoding]::new($false).GetBytes($TaskText)
    $taskFile = [IO.FileStream]::new($TaskPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try { $taskFile.Write($taskBytes,0,$taskBytes.Length); $taskFile.Flush($true) }
    finally { $taskFile.Dispose() }
}

try {
    $taskReview = Join-Path $taskRoot 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json'
    $taskOwner = Join-Path $taskRoot 'docs/verification/wave5/runtime-owner-decision-20261012-r5.json'
    if ((Get-FileHash -LiteralPath $taskReview).Hash.ToLowerInvariant() -ne 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3' -or
        (Get-FileHash -LiteralPath $taskOwner).Hash.ToLowerInvariant() -ne '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab') { throw 'EXACT_APPROVAL_REQUIRED' }
    if ($ValidateOnly) {
        @{kind='wave5-exact-owner-reply-import-validation';passed=$true;
          transcriptRead=$false;credentialsRead=$false;networkCalls=0;filesCreated=0} | ConvertTo-Json -Compress
        exit 0
    }
    if (Test-Path -LiteralPath $taskReadyFile) { throw 'EXISTING_PRIVATE_INPUT_PRESERVED' }
    $taskPhase = 'exact-user-reply-read'
    $taskStream = [IO.FileStream]::new($taskTranscript,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $taskReader = [IO.StreamReader]::new($taskStream)
    $taskReuseAuthorized = $false
    $taskCredentialMatches = 0
    while ($null -ne ($taskLine = $taskReader.ReadLine())) {
        if (-not $taskLine.Contains('call_85e76c1e42c0441bae47f7f63607cc43') -and
            -not $taskLine.Contains('call_637ea7df9a28457388be21396163da04')) { continue }
        $taskRecord = $taskLine | ConvertFrom-Json
        if ($taskRecord.type -ne 'response_item' -or $taskRecord.payload.role -ne 'user') { continue }
        foreach ($taskContent in $taskRecord.payload.content) {
            if ($taskContent.type -ne 'input_text') { continue }
            if ($taskContent.text -notmatch '^\s*<send_user_message_question_reply>') { continue }
            # The desktop's reply marker can have an opening tag only.
            # Parse the entire remaining JSON; never extract a permissive token
            # match from arbitrary quoted text or assistant/tool records.
            $taskReplyJson = [regex]::Replace($taskContent.text,'^\s*<send_user_message_question_reply>\s*','')
            $taskReplyJson = [regex]::Replace($taskReplyJson,'\s*</send_user_message_question_reply>\s*$','')
            foreach ($taskQuestion in ($taskReplyJson | ConvertFrom-Json)) {
                if ($taskQuestion.questionItemId -eq $taskReuseQuestion -and $taskQuestion.answer -eq $taskReuseText) { $taskReuseAuthorized = $true }
                if ($taskQuestion.questionItemId -eq $taskCredentialQuestion) {
                    $taskCredentialMatches++
                    $taskPlain = [string]$taskQuestion.answer
                }
            }
        }
    }
    $taskReader.Dispose(); $taskReader = $null
    if (-not $taskReuseAuthorized -or $taskCredentialMatches -ne 1 -or
        $taskPlain -notmatch '^sbp_[A-Za-z0-9_-]{20,200}$') { throw 'EXACT_DIRECT_USER_INPUT_REQUIRED' }
    $taskPhase = 'private-dpapi-encryption'
    $taskSecret = ConvertTo-SecureString -String $taskPlain -AsPlainText -Force
    $taskPlain = $null
    $taskCipher = ConvertFrom-SecureString -SecureString $taskSecret
    $taskSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $taskPhase = 'private-folder-creation'
    $taskPrivateFolder = Join-Path ([IO.Path]::GetTempPath()) ('JentraOS-Wave5-owner-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($taskPrivateFolder)
    $taskAcl = [Security.AccessControl.DirectorySecurity]::new()
    $taskAcl.SetOwner($taskSid); $taskAcl.SetAccessRuleProtection($true,$false)
    [void]$taskAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($taskSid,
        [Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    $taskPhase = 'private-current-user-acl'
    Set-Acl -LiteralPath $taskPrivateFolder -AclObject $taskAcl
    $taskSealedPath = Join-Path $taskPrivateFolder 'owner-pat.dpapi'
    $taskPhase = 'private-ciphertext-write'
    Write-TaskNewFile $taskSealedPath $taskCipher
    $taskNow = [DateTimeOffset]::UtcNow
    $taskMetadata = [ordered]@{
        kind='wave5-private-owner-input-metadata'; projectId='xpdoufauvrbdmxgngetv';
        runtimeBundleSha256='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
        ownerSid=$taskSid.Value;createdAt=$taskNow.ToString('o');expiresAt=$taskNow.AddHours(2).ToString('o');
        purpose='Exact already-approved isolated setup; direct human instruction to use supplied credential';
        inputSource='Exact current-chat human reply; no other stored credential read';
        inputQuestionId=$taskCredentialQuestion;reuseAuthorizationQuestionId=$taskReuseQuestion;
        storage='Windows CurrentUser DPAPI; current SID only protected ACL';
        privateFolder=$taskPrivateFolder;sealedTokenPath=$taskSealedPath;
        helperSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
        containsPlaintextCredential=$false;networkCalls=0;databaseWrites=0;authWrites=0
    }
    $taskText = ($taskMetadata | ConvertTo-Json) + [Environment]::NewLine
    $taskPhase = 'private-metadata-write'
    Write-TaskNewFile (Join-Path $taskPrivateFolder 'metadata.json') $taskText
    Write-TaskNewFile $taskReadyFile $taskText
    @{kind='wave5-exact-owner-reply-private-import';passed=$true;directReuseAuthorized=$true;
      plaintextCredentialPrintedOrWritten=$false;networkCalls=0;databaseWrites=0;authWrites=0} | ConvertTo-Json -Compress
} catch {
    @{failureCode='EXACT_OWNER_REPLY_PRIVATE_IMPORT_FAILED';phase=$taskPhase;
      credentialReplyMatches=$taskCredentialMatches;directReuseAuthorized=$taskReuseAuthorized;
      exceptionType=$_.Exception.GetType().FullName;credentialPrinted=$false;networkCalls=0} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($null -ne $taskReader) { $taskReader.Dispose() }
    if ($null -ne $taskSecret) { $taskSecret.Dispose() }
    $taskPlain = $null; $taskCipher = $null; $taskLine = $null; $taskRecord = $null; $taskQuestion = $null; $taskContent = $null; $taskReplyJson = $null
}
