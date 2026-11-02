// Read-only diagnostics. Never print management tokens, SMTP passwords, client
// keys, provider secrets, user lists or raw management responses.
const token=process.env.SUPABASE_ACCESS_TOKEN;
const project='xpdoufauvrbdmxgngetv';
if(!token){console.log(JSON.stringify({project,managementAccess:'missing'}));process.exitCode=2;}
else{
 try{
  const response=await fetch(`https://api.supabase.com/v1/projects/${project}/config/auth`,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(30000)});
  if(!response.ok){console.log(JSON.stringify({project,managementAccess:'unavailable',httpStatus:response.status}));process.exitCode=2;}
  else{
   const config=await response.json();
   console.log(JSON.stringify({project,managementAccess:'available',siteUrl:config.site_url,redirectAllowlist:config.uri_allow_list,emailEnabled:config.external_email_enabled,signupDisabled:config.disable_signup,emailAutoconfirm:config.mailer_autoconfirm,smtp:{host:config.smtp_host,port:config.smtp_port,user:config.smtp_user,sender:config.smtp_admin_email,senderName:config.smtp_sender_name,passwordState:config.smtp_pass?'present-or-redacted':'not-returned-or-unset'},passwordMinimum:config.password_min_length,passwordRequirements:config.password_required_characters,googleEnabled:config.external_google_enabled},null,2));
  }
 }catch{console.log(JSON.stringify({project,managementAccess:'request-failed',detailsRedacted:true}));process.exitCode=2;}
}
