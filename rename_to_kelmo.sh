#!/usr/bin/env bash
# Run from the Flutter project root:  bash rename_to_kelmo.sh
# Renames Rugal Scan -> Kelmo Scan (pubspec name, applicationId, Kotlin package, app label).
set -euo pipefail
OLD_PKG="com.rugal.rugal_scan";  NEW_PKG="com.kelmo.scan"
OLD_NAME="rugal_scan";           NEW_NAME="kelmo_scan"
LABEL="Kelmo Scan"

sed -i "s/^name: ${OLD_NAME}/name: ${NEW_NAME}/" pubspec.yaml
sed -i "s/${OLD_PKG}/${NEW_PKG}/g" android/app/build.gradle.kts

OLD_DIR="android/app/src/main/kotlin/com/rugal/rugal_scan"
NEW_DIR="android/app/src/main/kotlin/com/kelmo/scan"
mkdir -p "$NEW_DIR"
mv "$OLD_DIR"/*.kt "$NEW_DIR"/
rm -rf android/app/src/main/kotlin/com/rugal
sed -i "s/^package .*/package ${NEW_PKG}/" "$NEW_DIR"/*.kt

sed -i "s/android:label=\"[^\"]*\"/android:label=\"${LABEL}\"/" android/app/src/main/AndroidManifest.xml
grep -rl "package:${OLD_NAME}/" test 2>/dev/null | xargs -r sed -i "s#package:${OLD_NAME}/#package:${NEW_NAME}/#g"

flutter clean && flutter pub get
echo "Done. NOTE: new applicationId = new app on the phone. Uninstall the old 'Rugal Scan' manually."
