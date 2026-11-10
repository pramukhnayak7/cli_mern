# Flutter App — Program Editor (GUI for your Node.js server)

This Flutter app lets your friends view and edit `p1.txt`, `p2.txt`, … on your phone's Node.js server (port 8050) with a friendly GUI — no command line needed after setup.

## What it does
- Scans `http://<PHONE_IP>:8050/p1` … `/p20` to find existing programs
- Shows a list of programs to tap and view
- Lets you edit text and save it back to the server
- No `index.html` — clean hidden API on your server

## One-time setup on your phone (Termux)

```bash
pkg update && pkg upgrade
pkg install git openjdk-17 wget curl unzip xz-utils
```

### Install Flutter SDK
```bash
cd ~
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz
tar xf flutter_linux_3.19.0-stable.tar.xz
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

> If `flutter doctor` shows missing Android pieces, run:
> ```bash
> flutter doctor --android-licenses
> ```

### Create the Flutter project
```bash
cd ~
flutter create flutter_app
```

Then **replace** `~/flutter_app/lib/main.dart` with the `main.dart` from this repo, and **replace** `~/flutter_app/pubspec.yaml` with this repo's `pubspec.yaml`.

### Get dependencies
```bash
cd ~/flutter_app
flutter pub get
```

## Run the app

You need an Android device or emulator. From Termux:

```bash
cd ~/flutter_app
flutter run
```

If you have an Android phone plugged in with USB debugging on, it will install and launch there.

## Before running — set your phone's IP

Open `lib/main.dart` and change this line to your phone's actual router IP:

```dart
text: 'http://192.168.1.5:8050',
```

Then save, and run `flutter run` again.

## How your friends use it

1. Make sure your Node.js server is running on Termux:
   ```bash
   cd ~/webserver
   node server.js
   ```
   It prints your phone's IP, e.g. `http://192.168.1.5:8050`

2. Friends open the Flutter app on their Android device.

3. They tap **"Scan Programs"** — the app fetches `p1.txt`, `p2.txt`, etc.

4. They tap a program to view it, edit the text, and tap **Save** to write it back to your server.

## Files in this repo

```
flutter_app/
├── pubspec.yaml        # Flutter dependencies (includes http package)
└── lib/main.dart       # The full GUI app code
```

You only need these two files — drop them into a fresh `flutter create flutter_app` project.
