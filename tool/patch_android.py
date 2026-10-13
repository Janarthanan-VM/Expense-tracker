"""Applies this app's Android settings to a freshly generated Flutter project.

Run from the generated project folder:  python3 ../tool/patch_android.py
Fails loudly if the Flutter template changed, so the build never silently
ships without these settings.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path("android/app")
manifest_path = ROOT / "src/main/AndroidManifest.xml"
gradle_path = ROOT / "build.gradle.kts"


def fail(msg: str) -> None:
    print(f"patch_android: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------- manifest
manifest = manifest_path.read_text()

if "POST_NOTIFICATIONS" not in manifest:
    manifest, n = re.subn(
        r"(\s*)<application",
        r'\1<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\1<application',
        manifest,
        count=1,
    )
    if n != 1:
        fail("could not find <application> in AndroidManifest.xml")

if "allowBackup" not in manifest:
    # Android auto-backup would restore the encrypted DB without its key.
    manifest = manifest.replace(
        "<application",
        '<application android:allowBackup="false" android:fullBackupContent="false"',
        1,
    )

components = """
        <service
            android:name=".PaymentNotificationListener"
            android:label="Expense Tracker payment detection"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
        <receiver
            android:name=".CategoryActionReceiver"
            android:exported="false" />
    </application>"""

if "PaymentNotificationListener" not in manifest:
    if manifest.count("</application>") != 1:
        fail("expected exactly one </application> in AndroidManifest.xml")
    manifest = manifest.replace("</application>", components.strip() , 1)

manifest_path.write_text(manifest)

# ---------------------------------------------------------------- gradle
gradle = gradle_path.read_text()

gradle, n = re.subn(
    r"minSdk\s*=\s*flutter\.minSdkVersion",
    "minSdk = maxOf(flutter.minSdkVersion, 23)",
    gradle,
)
if n == 0 and "minSdk = maxOf(" not in gradle:
    fail("could not find minSdk in build.gradle.kts")

if "junit:junit" not in gradle:
    gradle += '\ndependencies {\n    testImplementation("junit:junit:4.13.2")\n}\n'

gradle_path.write_text(gradle)

print("patch_android: manifest and gradle updated")
