#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

swift build -c release --product pi-shell

TRIPLE="$(uname -m)-apple-macosx"
BINARY=".build/$TRIPLE/release/pi-shell"
APP_DIR=".build/Pi Shell.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [ ! -x "$BINARY" ]; then
  echo "error: missing built binary at $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/pi-shell"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Pi Shell</string>
  <key>CFBundleExecutable</key>
  <string>pi-shell</string>
  <key>CFBundleIdentifier</key>
  <string>pt.telecom.PiSwiftShell</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Pi Shell</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Pi Shell uses the microphone for system dictation in the composer.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Pi Shell uses speech recognition when dictating prompts.</string>
</dict>
</plist>
PLIST

INTENTS_DIR="$RESOURCES/Metadata.appintents"
mkdir -p "$INTENTS_DIR"
cat > "$INTENTS_DIR/version.json" <<'JSON'
{
  "version" : "3.0",
  "toolsVersion" : "manual"
}
JSON
cat > "$INTENTS_DIR/extract.actionsdata" <<'JSON'
{
  "actions": {
    "AskPiShellIntent": {
      "identifier": "AskPiShellIntent",
      "fullyQualifiedTypeName": "PiSwiftShellApp.AskPiShellIntent",
      "title": { "key": "Ask Pi Shell" },
      "descriptionMetadata": {
        "descriptionText": { "key": "Send a prompt to the current Pi Shell agent session." },
        "searchKeywords": []
      },
      "isDiscoverable": true,
      "openAppWhenRun": true,
      "parameters": [
        {
          "name": "prompt",
          "title": { "key": "Prompt" },
          "isOptional": false,
          "isInput": true,
          "valueType": { "primitive": { "wrapper": { "typeIdentifier": 0 } } }
        },
        {
          "name": "session",
          "title": { "key": "Session" },
          "isOptional": false,
          "isInput": false,
          "valueType": { "entity": { "wrapper": { "typeName": "PiShellSessionEntity" } } }
        }
      ],
      "actionConfiguration": {
        "actionSummary": {
          "wrapper": {
            "summaryString": {
              "formatString": "Ask Pi Shell ${prompt}",
              "parameterIdentifiers": ["prompt"]
            },
            "otherParameterIdentifiers": ["session"]
          }
        }
      },
      "visibilityMetadata": { "isDiscoverable": true, "assistantOnly": false }
    },
    "NewPiShellSessionIntent": {
      "identifier": "NewPiShellSessionIntent",
      "fullyQualifiedTypeName": "PiSwiftShellApp.NewPiShellSessionIntent",
      "title": { "key": "Start New Pi Shell Session" },
      "descriptionMetadata": {
        "descriptionText": { "key": "Clear the visible chat and start a fresh Pi Shell agent session." },
        "searchKeywords": []
      },
      "isDiscoverable": true,
      "openAppWhenRun": true,
      "parameters": [],
      "actionConfiguration": {
        "actionSummary": {
          "wrapper": {
            "summaryString": {
              "formatString": "Start a new Pi Shell session",
              "parameterIdentifiers": []
            },
            "otherParameterIdentifiers": []
          }
        }
      },
      "visibilityMetadata": { "isDiscoverable": true, "assistantOnly": false }
    },
    "OpenPiShellIntent": {
      "identifier": "OpenPiShellIntent",
      "fullyQualifiedTypeName": "PiSwiftShellApp.OpenPiShellIntent",
      "title": { "key": "Open Pi Shell" },
      "descriptionMetadata": {
        "descriptionText": { "key": "Open Pi Shell." },
        "searchKeywords": []
      },
      "isDiscoverable": true,
      "openAppWhenRun": true,
      "parameters": [],
      "actionConfiguration": {
        "actionSummary": {
          "wrapper": {
            "summaryString": {
              "formatString": "Open Pi Shell",
              "parameterIdentifiers": []
            },
            "otherParameterIdentifiers": []
          }
        }
      },
      "visibilityMetadata": { "isDiscoverable": true, "assistantOnly": false }
    }
  },
  "entities": {
    "PiShellSessionEntity": {
      "identifier": "PiShellSessionEntity",
      "displayRepresentation": { "title": { "key": "Pi Shell Session" } },
      "properties": []
    }
  },
  "queries": {},
  "enums": {}
}
JSON

echo "Built $APP_DIR"
