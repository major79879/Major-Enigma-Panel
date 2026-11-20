#!/bin/sh
# Major Enigma Panel installer / updater  -  يوضع في جذر المستودع، و REPO يشير إلى مجلد MajorPanel
# الاستخدام:  sh installer.sh            (يثبّت ثم يعيد تشغيل الواجهة بعد 5 ثوانٍ)
#             sh installer.sh norestart  (يثبّت فقط - يستخدمه زر التحديث داخل البانل)
# لتغيير المستودع عدّل BASE فقط (ونفس العنوان GITHUB_RAW في أول plugin.py)

printf '%s\n' '==============================================='
printf '%s\n' '   __  __    ___         _     ___     ____    '
printf '%s\n' '  |  \/  |  / _ \       | |   / _ \   |  _ \   '
printf '%s\n' '  | |\/| | | |_| |      | |  | | | |  | |_) |  '
printf '%s\n' '  | |  | | |  _  |   _ _| |  | |_| |  |  _ <   '
printf '%s\n' '  |_|  |_| |_| |_|   \___/    \___/   |_| \_\  '
printf '%s\n' '   ____      ___     _   _    _____    _       '
printf '%s\n' '  |  _ \    / _ \   | \ | |  | ____|  | |      '
printf '%s\n' '  | |_) |  | |_| |  |  \| |  |  _|    | |      '
printf '%s\n' '  |  __/   |  _  |  | |\  |  | |___   | |___   '
printf '%s\n' '  |_|      |_| |_|  |_| \_|  |_____|  |_____|  '
printf '%s\n' '==============================================='
printf '%s\n' '           MAJOR ENIGMA PANEL UPDATER          '
printf '%s\n' '            Developed by: John Kamel           '
printf '%s\n' '==============================================='

BASE="https://raw.githubusercontent.com/major79879/Major-Enigma-Panel/refs/heads/main"
REPO="$BASE/MajorPanel"
DIR="/usr/lib/enigma2/python/Plugins/Extensions/MajorPanel"
TMP=""

C0='\033[0m'; CB='\033[0;34m'; CC='\033[0;36m'; CG='\033[0;32m'; CY='\033[1;33m'; CR='\033[1;31m'
say() { printf '%b%s%b\n' "$1" "$2" "$C0"; }

if [ "$(id -u)" -ne 0 ]; then
    say "$CR" "> Run this installer as root."
    exit 1
fi

if ! command -v wget >/dev/null 2>&1; then
    say "$CR" "> wget is required but was not found."
    exit 1
fi

TMP=$(mktemp -d /tmp/majorpanel_update.XXXXXX) || {
    say "$CR" "> Could not create a temporary directory."
    exit 1
}

say "$CC" "=========================================================="
say "$CY" "===              Major Enigma Panel                    ==="
say "$CC" "=========================================================="
echo ""

# 1) حمّل كل الملفات أولاً - لا نلمس النسخة المثبتة إلا بعد نجاح التحميل كاملاً
for f in __init__.py lstparser.py plugin.py assets.py plugin.png; do
    say "$CB" "> Downloading $f ..."
    # __init__.py فارغ بطبيعته، لذلك لا نفحص حجمه
    if ! wget -q "$REPO/$f" -O "$TMP/$f" || { [ "$f" != "__init__.py" ] && [ ! -s "$TMP/$f" ]; }; then
        say "$CR" "> Failed to download: $f"
        say "$CR" "> Nothing was changed."
        rm -rf "$TMP"
        exit 1
    fi
done

# 1-أ) الخطوط المطلوبة للبانل.
FONTS="DejaVuSansMono.ttf"
mkdir -p "$TMP/fonts" || {
    say "$CR" "> Could not create the fonts directory."
    rm -rf "$TMP"
    exit 1
}
for f in $FONTS; do
    say "$CB" "> Downloading fonts/$f ..."
    if ! wget -q "$REPO/fonts/$f" -O "$TMP/fonts/$f" || [ ! -s "$TMP/fonts/$f" ]; then
        say "$CR" "> Failed to download: fonts/$f"
        say "$CR" "> Nothing was changed."
        rm -rf "$TMP"
        exit 1
    fi
done

# 1-ب) صور الأجهزة (اختيارية): مجلد boxes داخل MajorPanel على GitHub.
#      لإضافة جهاز جديد: ارفع صورته إلى MajorPanel/boxes/ بالاسم  <موديل الجهاز>.png  ثم أضف اسمها هنا.
#      فشل تحميل أي صورة لا يوقف التثبيت (تُتجاهل فقط).
BOXES="sf8008.png sf8008m.png"
mkdir -p "$TMP/boxes" || {
    say "$CR" "> Could not create the boxes directory."
    rm -rf "$TMP"
    exit 1
}
for f in $BOXES; do
    say "$CB" "> Downloading boxes/$f ..."
    if ! wget -q "$REPO/boxes/$f" -O "$TMP/boxes/$f" || [ ! -s "$TMP/boxes/$f" ]; then
        say "$CY" "> Skipped (not found): boxes/$f"
        rm -f "$TMP/boxes/$f"
    fi
done

# 2) ثبّت
say "$CB" "> Installing files ..."
mkdir -p "$DIR/boxes" "$DIR/fonts" || {
    say "$CR" "> Could not create the installation directories."
    rm -rf "$TMP"
    exit 1
}
cp -rf "$TMP"/. "$DIR"/ || { say "$CR" "> Copy failed"; rm -rf "$TMP"; exit 1; }
say "$CB" "> Setting file permissions ..."
if ! find "$DIR" -type d -exec chmod 755 {} \; || ! find "$DIR" -type f -exec chmod 644 {} \;; then
    say "$CR" "> Could not set file permissions."
    rm -rf "$TMP"
    exit 1
fi
say "$CB" "> Cleaning temporary files ..."
rm -rf "$TMP"

echo ""
say "$CC" "=========================================================="
say "$CG" "===              Installation Successful!              ==="
say "$CY" "===              Major Enigma Panel                    ==="
say "$CB" "===              By John Kamel                         ==="
say "$CC" "=========================================================="
echo ""

# 3) إعادة تشغيل الواجهة (إلا عند استدعائه من داخل البانل)
if [ "$1" != "norestart" ]; then
    say "$CY" "Enigma2 will restart automatically after 5 seconds..."
    i=5
    while [ "$i" -gt 0 ]; do
        say "$CY" "Restarting in $i seconds..."
        sleep 1
        i=$((i - 1))
    done
    say "$CG" "> Restarting Enigma2..."
    if ! killall enigma2; then
        say "$CR" "> Installation succeeded, but Enigma2 could not be restarted."
        exit 1
    fi
fi
exit 0
