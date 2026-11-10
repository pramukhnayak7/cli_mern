# Flutter Prog Server — the app IS the server

Your friends install **one APK**. The app runs an HTTP server on port 8050 on your phone.
From any laptop on the same Wi-Fi:

```bash
curl -s http://<PHONE_IP>:8050/p1 | xclip -selection clipboard
```

No Termux server, no `node`, no copying files. The app handles everything.

## What's inside

```
flutter_server_app/
├── pubspec.yaml            # Flutter + path_provider
├── lib/main.dart           # Full code: HTTP server + Flutter GUI editor
├── android/app/src/main/AndroidManifest.xml  # INTERNET permission
└── README.md
```

## One-time setup on your phone (Termux)

```bash
pkg update && pkg upgrade
pkg install git openjdk-17 wget curl unzip xz-utils

cd ~
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz
tar xf flutter_linux_3.19.0-stable.tar.xz
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

flutter doctor
flutter doctor --android-licenses   # accept all
```

## Create project + add files

```bash
cd ~
flutter create prog_server
```

Replace these files in `~/prog_server/` with the ones from this repo:

- `pubspec.yaml`
- `lib/main.dart`
- `android/app/src/main/AndroidManifest.xml`

## Get packages & build APK

```bash
cd ~/prog_server
flutter pub get
flutter build apk --release
```

The APK is at:
```
~/prog_server/build/app/outputs/flutter-apk/app-release.apk
```

Install it on your phone:
```bash
pm install -r ~/prog_server/build/app/outputs/flutter-apk/app-release.apk
```

## How friends use it

1. Open the app on your phone. It shows:
   ```
   Server: http://192.168.1.5:8050
   ```
2. Friends on the same Wi-Fi run from their laptop:
   ```bash
   curl -s http://192.168.1.5:8050/p1 | xclip -selection clipboard
   ```
3. In the app, tap any `pN.txt` to view and edit it, then tap **Save**.
4. The app also serves a browser editor at `http://<PHONE_IP>:8050/admin` if you want to edit from a laptop browser too.

## Files created by the app

Stored in the app's documents directory (private to the app):
- `p1.txt`, `p2.txt`, `p3.txt`, `p4.txt`, `p5.txt` (defaults)
- Tap the **+** button to create more (`p6.txt`, etc.)
