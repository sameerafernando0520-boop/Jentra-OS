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
