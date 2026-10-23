{{flutter_js}}
{{flutter_build_config}}

// Keep the rendering engine on this origin. Hosting CSP deliberately permits
// no third-party script, font, analytics or Firebase Auth resource.
// No caching service worker is installed for private employee sessions.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    forceSingleThreadedSkwasm: true,
  },
});
