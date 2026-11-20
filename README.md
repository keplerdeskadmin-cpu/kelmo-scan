# Kelmo Scan

Flutter document scanner for Android — camera scan with auto edge detection, crop/warp, filters (grayscale, magic color, photo, black & white), English + Urdu OCR (Tesseract), passport MRZ, redaction, ID card front/back on one page, PDF export, share, PIN + fingerprint lock, themes, backup.

- Dart UI: `lib/`
- Native engine (Kotlin, OpenCV 4.9 + tesseract4android): `android/app/src/main/kotlin/com/kelmo/scan/`
- OCR data: `android/app/src/main/assets/tessdata/` (eng, urd)

## Build
GitHub Actions builds the APK on every push (see the **Releases** page).
Locally: `flutter pub get && flutter build apk --release --split-per-abi`

License: GPLv3 (see `LICENSE`).
