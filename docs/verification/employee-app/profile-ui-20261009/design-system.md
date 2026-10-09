# Employee personal workspace — 0.3.0

Audience: employees using their own connected HR identity on a phone. This continues the approved Jentra mark and existing Manrope/Noto Sinhala/Noto Tamil typography. The layout below is a new design choice for the user's request for a proper, creative interface.

Four visual traits: personal (real employee name and own photo), focused (one immediate review action), composed (group related services rather than repeat large tiles), and clear (visible labels, storage limits, and unavailable states).

## Tokens and rules

- Retain the Jentra semantic blue action, pale blue information surface, navy text, and existing light/dark surfaces. Identity hero: navy #10283F, white text #FFFFFF, secondary #C9DAEA. Decorative arcs use white at 6%; they carry no information.
- Manrope titles 26/20/17; body 15/16; helper copy 13. Sinhala and Tamil retain the established Noto fallbacks. Names wrap naturally.
- Page gutter 20; section gap 16; inner spacing 8/12/16/20. Hero radius 28; grouped records 22; controls 16. Avatar circle 64 on Home, 96 on Profile.
- Consistent outlined service icons; no emoji, fake employee faces, synthetic pay figures, or status badges without source data.
- Each tappable row is at least 64 high; photo/navigation controls retain at least 48 logical-pixel targets. Large text and translated navigation use the compact three-tab layout, with Leave accessible from Home and More.
- Avatar selection uses the native system selector. Center-crop and reduce to 256 pixels, strip source metadata, save in the protected device store, and show initials on removal. Profile text states that photos are on this device and are removed at sign-out.
- Motion is brief and respects the platform disable-animation preference. No decorative looping animation. Light and dark share hierarchy and contrast.

## Application examples

Home: navy identity hero with avatar, employee name and workplace; a compact review card with a real count and explicit action; grouped Leave, Pay and HR-help rows; accessible floating dock with a short selected icon capsule.

Profile: centered avatar and employee identity within the same graphic language; choose/change/remove controls; visible device-storage explanation; one grouped employer record with company, legal entity, branch and timezone. The authoritative employer fields remain read-only.

## Implementation boundaries

Read-only development catalog check on 2026-10-09 found no avatar/photo function in api/public and no avatar/photo column in api/people/people_private/hr_private/core. The feature deliberately saves only on this device. Cloud synchronization requires an authorized server contract and deployment; no new public bucket, permissions, or migration is installed by this change.

Source-render examples and automated tests are evidence of this build's layouts and behavior. Android gallery interaction on a physical phone and iOS compilation/acceptance remain separate checks.

Native selector references: [Android photo picker](https://developer.android.com/training/data-storage/shared/photopicker), [Android document selector](https://developer.android.com/training/data-storage/shared/documents-files), [Apple PHPicker](https://developer.apple.com/documentation/photosui/phpickerviewcontroller).

The iOS source uses the current Flutter registrar's viewController property and ImageIO thumbnail creation with orientation correction: [Flutter registrar](https://api.flutter.dev/ios-embedder/protocol_flutter_plugin_registrar-p.html), [Apple ImageIO thumbnail](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)). These API checks are source review, not an iOS compile result.
