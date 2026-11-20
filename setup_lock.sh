#!/usr/bin/env bash
# Run from the Flutter project root AFTER copying lib/ and the 2 Kotlin files:  bash setup_lock.sh
set -euo pipefail
G=android/app/build.gradle.kts
M=android/app/src/main/AndroidManifest.xml

echo "1) crypto package (PIN hashing)"
flutter pub add crypto

echo "2) BiometricPrompt + AppCompat dependencies"
grep -q androidx.biometric "$G" || sed -i '/androidx.exifinterface/a implementation("androidx.biometric:biometric:1.1.0")' "$G"
grep -q "androidx.appcompat" "$G" || sed -i '/androidx.exifinterface/a implementation("androidx.appcompat:appcompat:1.6.1")' "$G"
grep -q androidx.biometric "$G" || { echo "!! dependency not added - paste $G"; exit 1; }

echo "3) USE_BIOMETRIC permission"
grep -q USE_BIOMETRIC "$M" || sed -i 's#<application#<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application#' "$M"

echo "4) AppCompat theme (BiometricPrompt needs it)"
for f in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  if [ -f "$f" ]; then
    sed -i 's#@android:style/Theme.Light.NoTitleBar#@style/Theme.AppCompat.Light.NoActionBar#; s#@android:style/Theme.Black.NoTitleBar#@style/Theme.AppCompat.NoActionBar#' "$f"
    echo "   patched $f"
  fi
done

flutter pub get
echo "Done. Now: flutter run"
