import 'package:flutter/widgets.dart';

import '../data/employee_account_actions.dart';

class EmployeeAccountStrings {
  EmployeeAccountStrings(BuildContext context)
    : language = Localizations.localeOf(context).languageCode;
  final String language;
  String _pick(String en, String si, String ta) => switch (language) {
    'si' => si,
    'ta' => ta,
    _ => en,
  };
  String get google => _pick(
    'Continue with Google',
    'Google සමඟ ඉදිරියට යන්න',
    'Google மூலம் தொடரவும்',
  );
  String get resend => _pick(
    'Resend confirmation',
    'තහවුරු කිරීම නැවත යවන්න',
    'உறுதிப்படுத்தலை மீண்டும் அனுப்பவும்',
  );
  String get login => _pick(
    'Username or work email',
    'පරිශීලක නාමය හෝ රාජකාරි ඊමේල් ලිපිනය',
    'பயனர்பெயர் அல்லது பணி மின்னஞ்சல்',
  );
  String get loginError => _pick(
    'Enter your username or work email.',
    'ඔබේ පරිශීලක නාමය හෝ රාජකාරි ඊමේල් ලිපිනය ඇතුළත් කරන්න.',
    'உங்கள் பயனர்பெயர் அல்லது பணி மின்னஞ்சலை உள்ளிடுங்கள்.',
  );
  String get username => _pick('Username', 'පරිශීලක නාමය', 'பயனர்பெயர்');
  String get usernameError => _pick(
    'Enter a valid username.',
    'වලංගු පරිශීලක නාමයක් ඇතුළත් කරන්න.',
    'சரியான பயனர்பெயரை உள்ளிடுங்கள்.',
  );
  String get temporaryPassword =>
      _pick('Temporary password', 'තාවකාලික මුරපදය', 'தற்காலிக கடவுச்சொல்');
  String get newPassword =>
      _pick('New password', 'නව මුරපදය', 'புதிய கடவுச்சொல்');
  String get confirmPassword => _pick(
    'Confirm new password',
    'නව මුරපදය තහවුරු කරන්න',
    'புதிய கடவுச்சொல்லை உறுதிப்படுத்தவும்',
  );
  String get passwordRequirements => _pick(
    'Use at least 12 characters, including uppercase and lowercase letters and a number.',
    'ලොකු අකුරු, කුඩා අකුරු සහ අංකයක් ඇතුළුව අවම වශයෙන් අක්ෂර 12ක් භාවිත කරන්න.',
    'பெரிய எழுத்து, சிறிய எழுத்து மற்றும் ஓர் எண் உட்பட குறைந்தது 12 எழுத்துகளைப் பயன்படுத்துங்கள்.',
  );
  String get passwordMismatch => _pick(
    'The passwords must match.',
    'මුරපද දෙක සමාන විය යුතුය.',
    'இரு கடவுச்சொற்களும் பொருந்த வேண்டும்.',
  );
  String get changeTemporaryPassword => _pick(
    'Change temporary password',
    'තාවකාලික මුරපදය වෙනස් කරන්න',
    'தற்காலிக கடவுச்சொல்லை மாற்றவும்',
  );
  String get changeTemporaryPasswordCopy => _pick(
    'Choose a new password before opening your employee workspace. You will then sign in again.',
    'සේවක වැඩබිම විවෘත කිරීමට පෙර නව මුරපදයක් තෝරන්න. ඉන්පසු නැවත පිවිසෙන්න.',
    'பணியாளர் பணியிடத்தைத் திறப்பதற்கு முன் புதிய கடவுச்சொல்லைத் தேர்வுசெய்து மீண்டும் உள்நுழையுங்கள்.',
  );
  String get passwordChanged => _pick(
    'Password changed. Sign in with your new password.',
    'මුරපදය වෙනස් කළා. නව මුරපදයෙන් පිවිසෙන්න.',
    'கடவுச்சொல் மாற்றப்பட்டது. புதிய கடவுச்சொல்லுடன் உள்நுழையுங்கள்.',
  );
  String get staffAccessPending => _pick(
    'Ask HR to activate your employee access.',
    'ඔබේ සේවක ප්‍රවේශය සක්‍රීය කිරීමට මානව සම්පත් අංශය අමතන්න.',
    'உங்கள் பணியாளர் அணுகலைச் செயல்படுத்த மனிதவளப் பிரிவை அணுகுங்கள்.',
  );
  String get staffUseDesktop => _pick(
    'Open Jentra OS to use your HR manager account.',
    'ඔබේ මානව සම්පත් කළමනාකරු ගිණුම භාවිත කිරීමට Jentra OS විවෘත කරන්න.',
    'உங்கள் மனிதவள மேலாளர் கணக்கைப் பயன்படுத்த Jentra OS ஐத் திறக்கவும்.',
  );
  String get resetUsernamePassword => _pick(
    'Reset username password',
    'පරිශීලක නාමයේ මුරපදය යළි සකසන්න',
    'பயனர்பெயரின் கடவுச்சொல்லை மீட்டமைக்கவும்',
  );
  String get sendRecoveryCode => _pick(
    'Request recovery code',
    'ප්‍රතිසාධන කේතයක් ඉල්ලන්න',
    'மீட்புக் குறியீட்டைக் கோருங்கள்',
  );
  String get recoveryRequested => _pick(
    'If recovery is available, a code will be sent to the verified email address.',
    'ප්‍රතිසාධනය කළ හැකි නම් තහවුරු කළ ඊමේල් ලිපිනයට කේතයක් යවනු ලැබේ.',
    'மீட்பு கிடைத்தால், சரிபார்க்கப்பட்ட மின்னஞ்சல் முகவரிக்கு ஒரு குறியீடு அனுப்பப்படும்.',
  );
  String get recoveryCode => _pick(
    'Six-digit recovery code',
    'ඉලක්කම් හයක ප්‍රතිසාධන කේතය',
    'ஆறு இலக்க மீட்புக் குறியீடு',
  );
  String get recoveryCodeError => _pick(
    'Enter the six-digit recovery code.',
    'ඉලක්කම් හයක ප්‍රතිසාධන කේතය ඇතුළත් කරන්න.',
    'ஆறு இலக்க மீட்புக் குறியீட்டை உள்ளிடுங்கள்.',
  );
  String get resetPassword => _pick(
    'Reset password',
    'මුරපදය යළි සකසන්න',
    'கடவுச்சொல்லை மீட்டமைக்கவும்',
  );
  String failure(EmployeeAccountFailure failure) => switch (failure) {
    EmployeeAccountFailure.googleDisabled => _pick(
      'Google sign-in is not enabled for this company. Ask your administrator to enable Google in Supabase.',
      'මෙම ආයතනයට Google පිවිසුම සක්‍රීය නැත. Supabase හි Google සක්‍රීය කිරීමට පරිපාලක අමතන්න.',
      'இந்த நிறுவனத்திற்கு Google உள்நுழைவு இயக்கப்படவில்லை. Supabase இல் Google ஐ இயக்க நிர்வாகியை அணுகவும்.',
    ),
    EmployeeAccountFailure.invalidEmail => _pick(
      'Enter your work email first.',
      'පළමුව ඔබගේ රැකියා ඊමේල් ලිපිනය ඇතුළත් කරන්න.',
      'முதலில் உங்கள் பணி மின்னஞ்சலை உள்ளிடவும்.',
    ),
    EmployeeAccountFailure.waitBeforeResend => _pick(
      'Wait a minute before requesting another email.',
      'තවත් ඊමේලයක් ඉල්ලීමට පෙර මිනිත්තුවක් රැඳී සිටින්න.',
      'மற்றொரு மின்னஞ்சலைக் கோருவதற்கு முன் ஒரு நிமிடம் காத்திருக்கவும்.',
    ),
    EmployeeAccountFailure.cancelled => _pick(
      'Google sign-in was cancelled. You can try again.',
      'Google පිවිසුම අවලංගු විය. නැවත උත්සාහ කළ හැක.',
      'Google உள்நுழைவு ரத்து செய்யப்பட்டது. மீண்டும் முயற்சிக்கலாம்.',
    ),
    EmployeeAccountFailure.signInRequired => _pick(
      'Your account changed. Return to your workspace.',
      'ඔබගේ ගිණුම වෙනස් විය. වැඩබිම වෙත ආපසු යන්න.',
      'உங்கள் கணக்கு மாறியுள்ளது. பணியிடத்திற்குத் திரும்பவும்.',
    ),
    EmployeeAccountFailure.callbackRejected => _pick(
      'This sign-in return could not be verified. Start Google sign-in again in this app.',
      'මෙම පිවිසුම් ආපසු පැමිණීම තහවුරු කළ නොහැක. යෙදුමෙන් Google පිවිසුම නැවත අරඹන්න.',
      'இந்த உள்நுழைவு திரும்பலைச் சரிபார்க்க முடியவில்லை. செயலியில் Google உள்நுழைவை மீண்டும் தொடங்கவும்.',
    ),
    EmployeeAccountFailure.unavailable => _pick(
      'Account access could not complete. Check your connection and ask your administrator to verify the sign-in provider and callback settings.',
      'ගිණුම් ප්‍රවේශය සම්පූර්ණ කළ නොහැක. සම්බන්ධතාව පරීක්ෂා කර පිවිසුම් සහ ආපසු පැමිණීමේ සැකසුම් තහවුරු කිරීමට පරිපාලක අමතන්න.',
      'கணக்கு அணுகலை முடிக்க முடியவில்லை. இணைப்பைச் சரிபார்த்து உள்நுழைவு மற்றும் திரும்பல் அமைப்புகளைச் சரிபார்க்க நிர்வாகியை அணுகவும்.',
    ),
  };
  String notice(EmployeeAccountNotice notice) => switch (notice) {
    EmployeeAccountNotice.googleOpened => _pick(
      'Finish Google sign-in in your browser, then return to Jentra Employee.',
      'බ්‍රවුසරයේ Google පිවිසුම සම්පූර්ණ කර Jentra Employee වෙත ආපසු එන්න.',
      'உலாவியில் Google உள்நுழைவை முடித்து Jentra Employee க்குத் திரும்பவும்.',
    ),
    EmployeeAccountNotice.confirmationRequested => _pick(
      'If this account needs confirmation, an email has been requested. Open the newest email on this device. HR membership and employee access are still required.',
      'මෙම ගිණුමට තහවුරු කිරීම අවශ්‍ය නම් ඊමේලයක් ඉල්ලා ඇත. මෙම උපාංගයේ නවතම ඊමේලය විවෘත කරන්න. HR සාමාජිකත්වය සහ සේවක ප්‍රවේශය තවමත් අවශ්‍යය.',
      'இந்தக் கணக்கிற்கு உறுதிப்படுத்தல் தேவைப்பட்டால் மின்னஞ்சல் கோரப்பட்டுள்ளது. இந்தச் சாதனத்தில் புதிய மின்னஞ்சலைத் திறக்கவும். HR உறுப்பினர் மற்றும் பணியாளர் அணுகல் இன்னும் தேவை.',
    ),
  };
}
