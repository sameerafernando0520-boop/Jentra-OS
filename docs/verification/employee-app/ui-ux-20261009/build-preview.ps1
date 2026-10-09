param([string]$OutputPath = (Join-Path $PSScriptRoot 'employee-app-preview.html'))
$ErrorActionPreference = 'Stop'
$screens = @(
    @{ Name = 'home-light-en'; Title = 'Your space'; Copy = 'A focused home with upcoming review receipts and compact service shortcuts.'; Group = 'core' },
    @{ Name = 'home-dark-en'; Title = 'Dark appearance'; Copy = 'The same employee experience in the Jentra dark palette.'; Group = 'core' },
    @{ Name = 'sign-in'; Title = 'Company sign-in'; Copy = 'Use an existing Jentra account. HR controls the accepted employee link.'; Group = 'core' },
    @{ Name = 'leave-draft'; Title = 'Private leave draft'; Copy = 'Save on this device. This does not submit a request to HR.'; Group = 'core' },
    @{ Name = 'activity'; Title = 'Activity'; Copy = 'Local drafts and shared reviews remain clearly separate from official HR submissions.'; Group = 'core' },
    @{ Name = 'more-dark'; Title = 'All services'; Copy = 'Profile, leave, work, pay, documents, HR help and private account controls.'; Group = 'core' },
    @{ Name = 'review-search'; Title = 'Find a review'; Copy = 'Search your loaded shared reviews and filter by receipt status.'; Group = 'core' },
    @{ Name = 'hr-help'; Title = 'Guided HR help'; Copy = 'Practical next steps for account access, leave, pay, reviews and documents.'; Group = 'core' },
    @{ Name = 'shared-review'; Title = 'Shared review'; Copy = 'Read the current review and explicitly acknowledge receipt.'; Group = 'core' },
    @{ Name = 'pay-availability'; Title = 'Payroll availability'; Copy = 'No invented salary or payment status. Employee payroll access is a remaining backend dependency.'; Group = 'core' },
    @{ Name = 'home-large-si'; Title = 'Sinhala at 200% text'; Copy = '360px phone width. Secondary destinations remain available through More.'; Group = 'accessibility' },
    @{ Name = 'home-large-ta'; Title = 'Tamil at 200% text'; Copy = '360px phone width with dark appearance and enlarged navigation.'; Group = 'accessibility' },
    @{ Name = 'sign-in-large-keyboard'; Title = 'Sign-in with a keyboard inset'; Copy = '200% text, 360px phone width and a simulated 280px keyboard inset. Scroll to reach the form action.'; Group = 'accessibility' }
)
$cards = foreach ($screen in $screens) {
    $imagePath = Join-Path $PSScriptRoot ('previews/' + $screen.Name + '.png')
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($imagePath))
    '<article data-group="{0}"><div class="caption"><h2>{1}</h2><p>{2}</p></div><img src="data:image/png;base64,{3}" alt="{1} rendered from the employee app" loading="lazy"></article>' -f $screen.Group, $screen.Title, $screen.Copy, $encoded
}
$html = @'
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Jentra Employee — UI upgrade</title>
<style>
:root{color-scheme:light;--ink:#10283f;--muted:#5b6d7e;--line:#dce5ed;--blue:#0064d9}*{box-sizing:border-box}body{margin:0;background:#f4f7fa;color:var(--ink);font:16px/1.55 system-ui,sans-serif}header,main,footer{max-width:1180px;margin:auto;padding:32px 24px}header{padding-top:48px}small{font-weight:650;color:var(--blue)}h1{font-size:clamp(32px,6vw,56px);letter-spacing:-.04em;margin:8px 0 12px;line-height:1.1}header p{max-width:760px;color:var(--muted)}.scope{padding:16px 20px;border:1px solid var(--line);background:#fff;border-radius:12px;max-width:900px}nav{display:flex;gap:12px;flex-wrap:wrap;margin-top:24px}button{font:inherit;min-height:48px;background:white;border:1px solid var(--line);border-radius:8px;padding:10px 18px;color:var(--ink);cursor:pointer}button[aria-pressed=true]{background:var(--blue);color:white;border-color:var(--blue)}button:focus-visible{outline:3px solid #68b7ff;outline-offset:3px}.screens{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:32px;align-items:start}article{border:1px solid var(--line);border-radius:18px;background:white;overflow:hidden}article[hidden]{display:none}.caption{padding:20px;min-height:154px}h2{font-size:20px;margin:0 0 8px}.caption p{font-size:14px;color:var(--muted);margin:0}img{display:block;width:100%;height:auto;border-top:1px solid var(--line)}footer{font-size:14px;color:var(--muted);padding-bottom:48px}@media(prefers-reduced-motion:no-preference){button{transition:background .15s}}@media(max-width:480px){header,main,footer{padding-left:16px;padding-right:16px}}
</style>
<header><small>DEVELOPMENT BUILD · 0.2.0 · 9 OCTOBER 2026</small><h1>Your work. Your space.</h1><p>A modern employee experience with a floating navigation dock, an activity hub, searchable reviews, a date-range picker and guided HR help.</p><div class="scope">These screens are rendered from the Flutter app with labeled development fixtures. They do not show real employee data or prove an authenticated device walkthrough. Attendance, leave submission and employee payslips remain backend dependencies.</div><nav aria-label="Preview filter"><button type="button" data-filter="all" aria-pressed="true">All screens</button><button type="button" data-filter="core" aria-pressed="false">Core experience</button><button type="button" data-filter="accessibility" aria-pressed="false">Large text and languages</button></nav></header>
<main><div class="screens">
'@
$html += $cards -join "`n"
$html += @'
</div></main><footer>This file contains every screenshot and works offline. Private drafts expire within 24 hours and never auto-submit. Android packaging, native acceptance, iOS signing and payroll readiness are separate verification steps.</footer>
<script>document.querySelectorAll('[data-filter]').forEach(button=>button.addEventListener('click',()=>{document.querySelectorAll('[data-filter]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));document.querySelectorAll('[data-group]').forEach(item=>item.hidden=button.dataset.filter!=='all'&&item.dataset.group!==button.dataset.filter)}));</script></html>
'@
[IO.File]::WriteAllText($OutputPath, $html, [Text.UTF8Encoding]::new($false))
Get-Item -LiteralPath $OutputPath | Select-Object FullName, Length
