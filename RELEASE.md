# Kelmo Scan – release checklist (later)

1. Icon: 1024x1024 PNG -> flutter_launcher_icons.
2. Signing: use your Kelmo keystore, `android/key.properties`, never commit it.
3. Build: `flutter build apk --release --split-per-abi` (smaller APKs) or `flutter build appbundle --release`.
4. GPLv3: keep the source public and link it in the store listing; keep LICENSE in the repo.
5. No proprietary SDKs are used (OCR = Tesseract) -> F-Droid compatible.
