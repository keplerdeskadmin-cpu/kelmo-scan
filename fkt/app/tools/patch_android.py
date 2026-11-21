"""Run after `flutter create .` in CI: permissions, name, icon, release signing."""
import pathlib, re, shutil
root = pathlib.Path(__file__).resolve().parent.parent
man = root / 'android/app/src/main/AndroidManifest.xml'
s = man.read_text()
perms = ['INTERNET', 'RECORD_AUDIO', 'VIBRATE']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms if p not in s)
s = s.replace('<application', add + '    <application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="FKT Messenger"', s, count=1)
if 'usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)
man.write_text(s)

res = root / 'android/app/src/main/res'
for d in (root / 'android_res').iterdir():
    if d.is_dir():
        (res / d.name).mkdir(parents=True, exist_ok=True)
        for f in d.iterdir():
            shutil.copy(f, res / d.name / f.name)

g = root / 'android/app/build.gradle.kts'
t = g.read_text()
sign = '''    val ks = System.getenv("KELMO_KEYSTORE")
    signingConfigs {
        if (ks != null && file(ks).exists()) {
            create("kelmo") {
                storeFile = file(ks)
                storePassword = System.getenv("KELMO_KEYSTORE_PASS")
                keyAlias = "kelmo"
                keyPassword = System.getenv("KELMO_KEYSTORE_PASS")
            }
        }
    }

    buildTypes {'''
assert '    buildTypes {' in t, 'buildTypes not found'
t = t.replace('    buildTypes {', sign, 1)
t = t.replace('signingConfig = signingConfigs.getByName("debug")',
              'signingConfig = signingConfigs.findByName("kelmo") ?: signingConfigs.getByName("debug")', 1)
g.write_text(t)
print('patched android project')
print(man.read_text())
