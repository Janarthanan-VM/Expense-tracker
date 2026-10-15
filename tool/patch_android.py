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

PERMISSIONS = [
    "android.permission.POST_NOTIFICATIONS",
    # Read bank SMS directly and import past ones (credit / debit tracking).
    "android.permission.RECEIVE_SMS",
    "android.permission.READ_SMS",
    # Scan & Pay reads UPI QR codes with the camera, inside the app.
    "android.permission.CAMERA",
]
for permission in PERMISSIONS:
    if permission in manifest:
        continue
    manifest, n = re.subn(
        r"(\s*)<application",
        rf'\1<uses-permission android:name="{permission}"/>\1<application',
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
            android:label="Dripless payment detection"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
        <receiver
            android:name=".CategoryActionReceiver"
            android:exported="false" />
        <receiver
            android:name=".SmsReceiver"
            android:permission="android.permission.BROADCAST_SMS"
            android:exported="true">
            <intent-filter>
                <action android:name="android.provider.Telephony.SMS_RECEIVED" />
            </intent-filter>
        </receiver>
    </application>"""

if "PaymentNotificationListener" not in manifest:
    if manifest.count("</application>") != 1:
        fail("expected exactly one </application> in AndroidManifest.xml")
    manifest = manifest.replace("</application>", components.strip() , 1)

# Android 11+ only lets the app see UPI apps it declares interest in.
UPI_QUERY = """
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="upi" />
        </intent>"""
if 'android:scheme="upi"' not in manifest:
    if "<queries>" in manifest:
        manifest = manifest.replace("<queries>", "<queries>" + UPI_QUERY, 1)
    else:
        manifest = manifest.replace("</manifest>", "    <queries>" + UPI_QUERY + "\n    </queries>\n</manifest>", 1)

for required in ["RECEIVE_SMS", "READ_SMS", "SmsReceiver", "PaymentNotificationListener", 'android:scheme="upi"']:
    if required not in manifest:
        fail(f"{required} missing from AndroidManifest.xml after patching")

# Name shown under the icon on the phone.
manifest, n = re.subn(r'android:label="[^"]*"', 'android:label="Dripless"', manifest, count=1)
if n != 1:
    fail("could not set the app name (android:label) in AndroidManifest.xml")

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

# Release signing: when CI has written dripless-release.jks (from the
# DRIPLESS_KEYSTORE secret), every build is signed with the same key, so a new
# APK installs over the old one and keeps the user's data.
if "dripless-release.jks" not in gradle:
    gradle += """
val driplessKeystore = file("dripless-release.jks")
if (driplessKeystore.exists()) {
    android {
        signingConfigs {
            create("dripless") {
                storeFile = driplessKeystore
                storePassword = System.getenv("DRIPLESS_KEY_PASSWORD")
                keyAlias = "dripless"
                keyPassword = System.getenv("DRIPLESS_KEY_PASSWORD")
            }
        }
        buildTypes.getByName("release").signingConfig = signingConfigs.getByName("dripless")
    }
}
"""

if "junit:junit" not in gradle:
    gradle += (
        "\ndependencies {\n"
        '    testImplementation("junit:junit:4.13.2")\n'
        "}\n"
    )

gradle_path.write_text(gradle)

print("patch_android: manifest and gradle updated")
