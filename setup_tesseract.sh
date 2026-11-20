#!/usr/bin/env bash
# Run from the Flutter project root AFTER copying lib/ and the 3 Kotlin files:  bash setup_tesseract.sh
set -euo pipefail

echo "1) removing Google ML Kit"
flutter pub remove google_mlkit_text_recognition || true
rm -f LICENSE-EXCEPTION.txt

echo "2) JitPack repository (Tesseract4Android is published there)"
if ! grep -q jitpack android/build.gradle.kts; then
  sed -i '0,/mavenCentral()/s//mavenCentral()\n        maven { url = uri("https:\/\/jitpack.io") }/' android/build.gradle.kts
fi
grep -q jitpack android/build.gradle.kts || { echo "!! jitpack not added - paste android/build.gradle.kts to Claude"; exit 1; }

echo "3) Tesseract4Android dependency"
if ! grep -q tesseract4android android/app/build.gradle.kts; then
  sed -i '/androidx.exifinterface/a implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")' android/app/build.gradle.kts
fi
grep -q tesseract4android android/app/build.gradle.kts || { echo "!! dependency not added - paste android/app/build.gradle.kts to Claude"; exit 1; }

echo "4) language data (tessdata_fast, Apache-2.0)"
D=android/app/src/main/assets/tessdata
mkdir -p "$D"
for L in eng urd; do
  curl -L -o "$D/$L.traineddata" "https://github.com/tesseract-ocr/tessdata_fast/raw/main/$L.traineddata"
  [ "$(stat -c%s "$D/$L.traineddata")" -gt 100000 ] || { echo "!! $L.traineddata download failed"; exit 1; }
done
ls -lh "$D"

flutter pub get
echo "Done. Now: flutter run"
