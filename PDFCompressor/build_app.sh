#!/bin/zsh
# 构建 release 版并打包为 build.noindex/PDF Compressor.app（内含独立 Python + pikepdf + Pillow）
set -euo pipefail
cd "${0:A:h}"

# python-build-standalone：可重定位的 CPython，固定版本并校验哈希
PY_TAG=20260924
PY_FILE="cpython-3.12.14+${PY_TAG}-aarch64-apple-darwin-install_only_stripped.tar.gz"
PY_SHA=c2edb321cd32ec2b170df208db0446dccc4398db602ca27cf2079098fb1f7d9d
PY_DEPS=(pikepdf==10.13.0.post1 pillow==10.3.0)
CACHE=.python-cache

# 1. 准备 Python（只在第一次或版本变化时执行）
if [[ ! -f $CACHE/python/.ready-$PY_TAG ]]; then
    rm -rf $CACHE && mkdir -p $CACHE/download
    curl -fL --progress-bar -o "$CACHE/download/$PY_FILE" \
        "https://github.com/astral-sh/python-build-standalone/releases/download/$PY_TAG/${PY_FILE//+/%2B}"
    echo "$PY_SHA  $CACHE/download/$PY_FILE" | shasum -a 256 -c -
    tar -xzf "$CACHE/download/$PY_FILE" -C $CACHE
    $CACHE/python/bin/python3 -I -m pip install --quiet --disable-pip-version-check --only-binary :all: $PY_DEPS
    # 删掉运行时用不到的部分
    rm -rf $CACHE/python/lib/python3.12/{test,idlelib,tkinter,turtledemo,ensurepip,lib2to3} \
           $CACHE/python/lib/python3.12/site-packages/pip* \
           $CACHE/python/lib/{tcl,tk,itcl,thread}* $CACHE/python/include $CACHE/python/share
    find $CACHE/python -name __pycache__ -prune -exec rm -rf {} +
    $CACHE/python/bin/python3 -I -c "import pikepdf, PIL; print('python ok: pikepdf', pikepdf.__version__, 'pillow', PIL.__version__)"
    touch $CACHE/python/.ready-$PY_TAG
fi

# 2. 编译 Swift 界面。明确使用 macOS 15 SDK，避免新版 Command Line Tools
# 默认选中 macOS 26 SDK，令产物意外带入新系统依赖。
SDK=$(xcrun --sdk macosx15.4 --show-sdk-path 2>/dev/null || xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --find swiftc)
mkdir -p .build/release .build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" "$SWIFTC" \
    -parse-as-library -O \
    -target arm64-apple-macosx15.0 \
    -sdk "$SDK" \
    Sources/PDFCompressor/*.swift \
    -o .build/release/PDFCompressor

# 3. 生成 macOS 多尺寸应用图标
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

# Documents 由 iCloud 同步，会给文件加 Finder 属性导致签名失败，所以先在临时目录组装和签名
STAGE=$(mktemp -d)
APP="$STAGE/PDF Compressor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PDFCompressor "$APP/Contents/MacOS/"
cp ../compress.py "$APP/Contents/Resources/"
cp .build/AppIcon.icns "$APP/Contents/Resources/"
cp -R $CACHE/python "$APP/Contents/Resources/python"
# 预编译字节码并一起签名；运行时用 -B 禁止 Python 再往 app 内写 __pycache__（否则会破坏签名）
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
    <key>CFBundleShortVersionString</key><string>1.1.3</string>
    <key>CFBundleVersion</key><string>5</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
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

# 4. 签名：清除扩展属性，先签内嵌的每个 Mach-O，再签整个 app
xattr -cr "$APP"
find "$APP/Contents/Resources/python" -type f \( -name "*.so" -o -name "*.dylib" -o -perm -u+x \) \
    -exec sh -c 'file -b "$1" | grep -q Mach-O && codesign --force --sign - "$1"' _ {} \; 2>/dev/null
codesign --force --sign - "$APP"
# 在临时目录验证：复制回 iCloud 同步的目录后，iCloud 会再加 Finder 属性，原地验证会误报
codesign --verify --deep --strict "$APP"

FINAL="build.noindex/PDF Compressor.app"  # .noindex：不被 Spotlight 索引，避免与已安装的版本重复
rm -rf "$FINAL" && mkdir -p build.noindex
ditto --noextattr --norsrc "$APP" "$FINAL"
rm -rf "$STAGE"
# 构建副本不登记到 LaunchServices，避免启动台 / Spotlight 中与已安装的版本重复
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$FINAL" 2>/dev/null || true
echo "✓ $FINAL ($(du -sh "$FINAL" | cut -f1))"
