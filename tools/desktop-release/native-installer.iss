; Compile-time definitions and the exact [Files] entries are generated from the
; verified release manifest. This installer never invokes PowerShell or .NET.
[Setup]
AppId=JentraOS-Desktop-{#Channel}
AppName={#ProductName}
AppVersion={#VersionName}
AppVerName={#ProductName} {#FullVersion}
AppPublisher=Jentra
DefaultDirName={localappdata}\Programs\{#InstallFolder}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupIconFile={#IconPath}
OutputDir={#OutputDirectory}
OutputBaseFilename={#OutputBaseName}
VersionInfoVersion={#VersionName}.{#BuildNumber}
Compression=lzma2/fast
SolidCompression=yes
SetupLogging=yes
CloseApplications=no
RestartApplications=no
UsePreviousAppDir=yes
Uninstallable=not IsStaging
CreateUninstallRegKey=not IsStaging
UninstallDisplayIcon={app}\releases\{#ReleaseId}\jentra_desktop.exe

[Languages]
Name: english; MessagesFile: compiler:Default.isl

[Tasks]
Name: desktopicon; Description: Create a desktop shortcut; Flags: unchecked; Check: not IsStaging

[Icons]
Name: {autoprograms}\{#ProductName}; Filename: {app}\releases\{#ReleaseId}\jentra_desktop.exe; WorkingDir: {app}\releases\{#ReleaseId}; Check: not IsStaging
Name: {autodesktop}\{#ProductName}; Filename: {app}\releases\{#ReleaseId}\jentra_desktop.exe; WorkingDir: {app}\releases\{#ReleaseId}; Tasks: desktopicon; Check: not IsStaging

[Run]
Filename: {app}\releases\{#ReleaseId}\jentra_desktop.exe; Description: Open {#ProductName}; Flags: postinstall unchecked skipifsilent; Check: not IsStaging

[Code]
function IsStaging: Boolean;
begin
  Result := ExpandConstant('{param:STAGING|0}') = '1';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var ExistingManifest: String;
begin
  Result := '';
  if (not IsStaging) and (StrToIntDef(GetPreviousData('BuildNumber', '0'), 0) > {#BuildNumber}) then
    Result := 'A newer Jentra OS build is installed. Use its retained previous release for an explicit rollback.';
  ExistingManifest := ExpandConstant('{app}\releases\{#ReleaseId}\release-manifest.json');
  if FileExists(ExistingManifest) then
    if Lowercase(GetSHA256OfFile(ExistingManifest)) <> '{#ManifestSha256}' then
      Result := 'This release identity already exists with different bytes. Choose a new release build; existing files were preserved.';
end;

procedure VerifyInstalledFile(RelativeName, ExpectedHash: String);
begin
  if Lowercase(GetSHA256OfFile(ExpandConstant('{app}\releases\{#ReleaseId}\') + RelativeName)) <> ExpectedHash then
    RaiseException('Installed file verification failed. Installation will be rolled back.');
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  if not IsStaging then SetPreviousData(PreviousDataKey, 'BuildNumber', '{#BuildNumber}');
end;
