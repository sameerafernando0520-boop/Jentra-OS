$ErrorActionPreference='Stop'
$head=(git rev-parse HEAD).Trim()
$tracked=@(git ls-files)
$headRows=@{}
git ls-tree -r HEAD | ForEach-Object { if($_ -match '^\d+ blob ([a-f0-9]+)\t(.+)$') { $headRows[$Matches[2]]=$Matches[1] } }
$indexRows=@{}
git ls-files -s | ForEach-Object { if($_ -match '^\d+ ([a-f0-9]+) 0\t(.+)$') { $indexRows[$Matches[2]]=$Matches[1] } }
$workingChanges=@(git diff --name-only HEAD)
$stagedChanges=@(git diff --cached --name-only)
$groups=[ordered]@{
  approved_goldens=@($tracked | Where-Object {$_ -match '/test/goldens/'});
  wave4=@($tracked | Where-Object {$_ -match '(?i)wave4|/features/(people|assets|projects|service)/|(?:^|/)(?:workforce|assets|projects|service|attendance|leave|payroll|organization|calendar|sensitive_(?:employee|payroll))[^/]*\.(?:dart|sql)$'});
  wave5=@($tracked | Where-Object {$_ -match '(?i)wave5|W5_01|process_metric|process_foundation'});
  stock_opening_acceptance=@($tracked | Where-Object {$_ -match '(?i)stock[-_]opening|stock_opening'});
}
$summary=[ordered]@{}
foreach($group in $groups.Keys) {
  $paths=@($groups[$group] | Sort-Object -Unique)
  $rows=@($paths | ForEach-Object {
    @{file=$_;current_sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant();head_blob=$headRows[$_];index_blob=$indexRows[$_];index_matches_head=($headRows[$_] -eq $indexRows[$_]);working_tree_matches_head=($_ -notin $workingChanges)}
  })
  $summary[$group]=@{count=$rows.Count;unchanged=(@($rows | Where-Object { !$_.index_matches_head -or !$_.working_tree_matches_head }).Count -eq 0);files=$rows}
}
$packagePath='docs/verification/remaining-wave3/database-installation-package-20261003.json'
$orderPath='docs/verification/remaining-wave3/migration-order-final-20260930-45.json'
$reusePath='docs/verification/remaining-wave3/database-verification-reuse-20261003.json'
$refreshPath='docs/verification/remaining-wave3/refresh-final-resume-20261003.json'
$package=Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
$order=Get-Content -LiteralPath $orderPath -Raw | ConvertFrom-Json
$reuse=Get-Content -LiteralPath $reusePath -Raw | ConvertFrom-Json
$refresh=Get-Content -LiteralPath $refreshPath -Raw | ConvertFrom-Json
$candidates=@(for($i=0;$i -lt $order.candidates.Count;$i++) {
  $row=$order.candidates[$i]
  $p=$package.candidates[$i]
  $r=$reuse.candidates[$i]
  $hash=(Get-FileHash -LiteralPath $row.path -Algorithm SHA256).Hash.ToLowerInvariant()
  @{file=$row.path;ordinal=$row.ordinal;version=$row.version;requires_previous_candidates=$row.requires_previous_candidates;current_sha256=$hash;reviewed_sha256=$row.sha256;
    current_hash_matches=($hash -eq $row.sha256 -and $hash -eq $p.sha256 -and $hash -eq $r.sha256);
    package_dependency_order_matches=($row.path -eq $p.path -and $row.ordinal -eq $p.ordinal -and $row.requires_previous_candidates -eq $p.requires_previous_candidates);
    reuse_dependency_order_matches=($row.path -eq $r.path -and $row.ordinal -eq $r.ordinal -and $row.requires_previous_candidates -eq $r.requires_previous_candidates);
    present_in_latest_installed_ledger=($row.version -in $refresh.migrations.version)}
})
$helpers=@($refresh.shared_helpers | ForEach-Object {
  $h=$_; $prior=$package.shared_helpers | Where-Object { $_.name -eq $h.name -and $_.signature -eq $h.signature }
  @{name=$h.name;signature=$h.signature;source_md5=$h.source_md5;matches_package=($prior.source_md5 -eq $h.source_md5)}
})
$sources=@($packagePath,$orderPath,$reusePath,$refreshPath | ForEach-Object { @{file=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()} })
$output=[ordered]@{
  observed_at=(Get-Date).ToUniversalTime().ToString('o');head=$head;
  boundary='Local read-only Git/worktree/index/source-hash audit paired to root latest recorded read-only database refresh. No new database query, writes, installation, native executable/authentication/load/visual acceptance or owner signoff.';
  protected_groups=$summary;protected_changed=@($workingChanges | Where-Object {$_ -in ($groups.Values | ForEach-Object {$_})});protected_staged=@($stagedChanges | Where-Object {$_ -in ($groups.Values | ForEach-Object {$_})});
  evidence_sources=$sources;database_refresh=@{file=$refreshPath;observed_at=$refresh.observed_at;project_id=$refresh.project_id;query=$refresh.query;installed_count=$refresh.migrations.Count;api_count=$refresh.api_catalogue.Count;latest_installed=$refresh.migrations[-1];shared_helpers=$helpers};
  candidates=@{count=$candidates.Count;all_hashes_match=(@($candidates | Where-Object {!$_.current_hash_matches}).Count -eq 0);all_dependency_order_matches=(@($candidates | Where-Object {!$_.package_dependency_order_matches -or !$_.reuse_dependency_order_matches}).Count -eq 0);none_installed=(@($candidates | Where-Object {$_.present_in_latest_installed_ledger}).Count -eq 0);files=$candidates}
}
$output | ConvertTo-Json -Depth 9 | Set-Content docs/verification/remaining-wave3/procurement-protected-invariants-20261003.json
$summary.Keys | ForEach-Object {Write-Output ($_+': '+$summary[$_].count+' files unchanged='+$summary[$_].unchanged)}
Write-Output ('Candidates: '+$output.candidates.count+' hashes='+$output.candidates.all_hashes_match+' order='+$output.candidates.all_dependency_order_matches+' noneInstalled='+$output.candidates.none_installed)
