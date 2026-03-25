# HeadSafe

> Headphone Safety for macOS.

A tiny macOS menu bar app that sets a maximum volume limit when headphones or earphones are connected.

## How it works

- Detects audio output device changes in real time via CoreAudio
- Wired headphones are automatically protected
- Bluetooth devices are classified using IOBluetooth (headset vs speaker)
- Built-in speakers and other accessories are always ignored
- You can manually override device classification if auto-detection gets it wrong

## Build & Run

```
swift build
swift run
```

## Install as an app

```
swift build -c release
mkdir -p HeadSafe.app/Contents/MacOS
cp .build/release/HeadSafe HeadSafe.app/Contents/MacOS/
```

Then move `HeadSafe.app` to `/Applications` and add it to Login Items to launch at startup.

## Requirements

- macOS 14+
- Swift 6.0+
