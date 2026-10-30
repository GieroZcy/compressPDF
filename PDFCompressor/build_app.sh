#!/bin/zsh
# 構建 release 版並打包為 build.noindex/PDF Compressor.app（內含獨立 Python + pikepdf + Pillow）
set -euo pipefail
cd "${0:A:h}"

# python-build-standalone：可重定位的 CPython，固定版本並校驗哈希
PY_TAG=20260924
PY_FILE="cpython-3.12.14+${PY_TAG}-aarch64-apple-darwin-install_only_stripped.tar.gz"
PY_SHA=c2edb321cd32ec2b170df208db0446dccc4398db602ca27cf2079098fb1f7d9d
PY_DEPS=(pikepdf==10.13.0.post1 pillow==10.3.0)
CACHE=.python-cache

# 1. 準備 Python（只在第一次或版本變化時執行）
if [[ ! -f $CACHE/python/.ready-$PY_TAG ]]; then
    rm -rf $CACHE && mkdir -p $CACHE/download
    curl -fL --progress-bar -o "$CACHE/download/$PY_FILE" \
        "https://github.com/astral-sh/python-build-standalone/releases/download/$PY_TAG/${PY_FILE//+/%2B}"
    echo "$PY_SHA  $CACHE/download/$PY_FILE" | shasum -a 256 -c -
    tar -xzf "$CACHE/download/$PY_FILE" -C $CACHE
    $CACHE/python/bin/python3 -I -m pip install --quiet --disable-pip-version-check --only-binary :all: $PY_DEPS
    # 刪掉運行時用不到的部分
    rm -rf $CACHE/python/lib/python3.12/{test,idlelib,tkinter,turtledemo,ensurepip,lib2to3} \
           $CACHE/python/lib/python3.12/site-packages/pip* \
           $CACHE/python/lib/{tcl,tk,itcl,thread}* $CACHE/python/include $CACHE/python/share
    find $CACHE/python -name __pycache__ -prune -exec rm -rf {} +
    $CACHE/python/bin/python3 -I -c "import pikepdf, PIL; print('python ok: pikepdf', pikepdf.__version__, 'pillow', PIL.__version__)"
    touch $CACHE/python/.ready-$PY_TAG
fi

# 2. 編譯 Swift 界面
swift build -c release

# 3. 生成 macOS 多尺寸應用圖標
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET" .build/AppIcon.icns
mkdir -p "$ICONSET"
sips -z 16 16 Assets/AppIcon.png --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 Assets/AppIcon.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 Assets/AppIcon.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 Assets/AppIcon.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 Assets/AppIcon.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 Assets/AppIcon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 Assets/AppIcon.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 Assets/AppIcon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 Assets/AppIcon.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 Assets/AppIcon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o .build/AppIcon.icns

# Documents 由 iCloud 同步，會給文件加 Finder 屬性導致簽名失敗，所以先在臨時目錄組裝和簽名
STAGE=$(mktemp -d)
APP="$STAGE/PDF Compressor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PDFCompressor "$APP/Contents/MacOS/"
cp ../compress.py "$APP/Contents/Resources/"
cp .build/AppIcon.icns "$APP/Contents/Resources/"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
cp -R $CACHE/python "$APP/Contents/Resources/python"
# 預編譯字節碼並一起簽名；運行時用 -B 禁止 Python 再往 app 內寫 __pycache__（否則會破壞簽名）
"$APP/Contents/Resources/python/bin/python3" -I -m compileall -q "$APP/Contents/Resources/python/lib/python3.12" >/dev/null || true

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PDF Compressor</string>
    <key>CFBundleDisplayName</key><string>PDF Compressor</string>
    <key>CFBundleIdentifier</key><string>local.pdfcompressor</string>
    <key>CFBundleExecutable</key><string>PDFCompressor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key><string>PDF</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Alternate</string>
        <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
    </dict></array>
</dict>
</plist>
EOF

# 4. 簽名：清除擴展屬性，先簽內嵌的每個 Mach-O，再簽整個 app
xattr -cr "$APP"
find "$APP/Contents/Resources/python" -type f \( -name "*.so" -o -name "*.dylib" -o -perm -u+x \) \
    -exec sh -c 'file -b "$1" | grep -q Mach-O && codesign --force --sign - "$1"' _ {} \; 2>/dev/null
codesign --force --sign - "$APP"
# 在臨時目錄驗證：複製回 iCloud 同步的目錄後，iCloud 會再加 Finder 屬性，原地驗證會誤報
codesign --verify --deep --strict "$APP"

FINAL="build.noindex/PDF Compressor.app"  # .noindex：不被 Spotlight 索引，避免與已安裝的版本重複
rm -rf "$FINAL" && mkdir -p build.noindex
ditto --noextattr --norsrc "$APP" "$FINAL"
rm -rf "$STAGE"
# 構建副本不登記到 LaunchServices，避免啟動台 / Spotlight 中與已安裝的版本重複
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$FINAL" 2>/dev/null || true
echo "✓ $FINAL ($(du -sh "$FINAL" | cut -f1))"
