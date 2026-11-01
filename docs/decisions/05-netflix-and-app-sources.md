# 05 Netflix casting and app sources

Type: research
Status: resolved

## Question

In Italy, as of October 2026, can the Netflix iPad app cast to an old cast-only Chromecast, and with which limits? For streaming apps installed directly on the projector (Netflix, Disney+, Prime Video), what is the safest download source, and how is each APK's authenticity checked on Windows before installing?

## Answer

Yes: in Italy the Netflix iPad app can still cast to an old cast-only Chromecast, on the Standard or Premium plan only (not the ad plan), up to 1080p, on the same Wi-Fi; Netflix has dropped casting elsewhere without notice, so this may not last. For apps on the projector, Netflix, Disney+ and Prime Video offer no download outside app stores, so the phone APKs come from APKMirror; each is checked on Windows with apksigner, its certificate compared with the APKMirror page and with older versions, then pinned. To check: the Chromecast's generation and the user's Netflix plan.

Findings: [research/05-netflix-and-app-sources.md](../research/05-netflix-and-app-sources.md)
