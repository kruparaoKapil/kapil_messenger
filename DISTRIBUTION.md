# Kapil Messenger - Distribution Guide

This guide explains how to package **Kapil Messenger** into installable files for macOS (`.dmg`) and Windows (`.exe`).

## 1. Building for macOS (`.dmg`)

> [!IMPORTANT]
> **Host Requirements:** You can only build macOS apps on a Mac, and Windows apps on a Windows computer. Cross-compilation (e.g., building an `.exe` on a Mac) is not supported by Flutter.

### Step 1: Generate the App Bundle
Run this command in your terminal:
```bash
flutter build macos
```
*Note: This builds for your current architecture (Intel or Silicon). To build for both, modify the "Architectures" setting in Xcode (Runner project -> Build Settings) to "Standard Architectures".*
The output will be located at: `build/macos/Build/Products/Release/Kapil Messenger.app`

### Step 2: Create the DMG
You can use the open-source `create-dmg` tool (install via `brew install create-dmg`) or the `flutter_distributor` package we just added.

To use `create-dmg`:
```bash
create-dmg \
  --volname "Kapil Messenger" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Kapil Messenger.app" 200 190 \
  --hide-extension "Kapil Messenger.app" \
  --app-drop-link 600 185 \
  "build/macos/KapilMessenger-Installer.dmg" \
  "build/macos/Build/Products/Release/Kapil Messenger.app"
```

---

## 2. Building for Windows (`.exe`)

### Step 1: Generate the Windows Files
On a Windows machine, run:
```powershell
flutter build windows
```
The output is in `build\windows\runner\Release`. **Note:** This folder contains the `.exe` and several `.dll` files. You cannot just share the `.exe` alone; you must share the whole folder or create an installer.

### Step 2: Create a Single Installer (.exe)
We have added the `msix` and `flutter_distributor` packages to make this easier.

**Option A: MSIX (Easy & Modern)**
Run this to generate a modern Windows installer:
```powershell
dart run msix:create
```

**Option B: Inno Setup (Traditional .exe Setup)**
1. Download and install [Inno Setup](https://jrsoftware.org/isdl.php).
2. Create a new script and point it to the `build\windows\runner\Release` folder.
3. It will compile everything into a single `Setup.exe`.

---

## 3. Automation with Flutter Distributor
We have included `flutter_distributor` which can handle both platforms with a single config file (`distributor.yaml`). 

To see all options, run:
```bash
dart run flutter_distributor --help
```
