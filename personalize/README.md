# LinPad M5 / 12 GB — فایل‌های شخصی‌سازی

این پوشه شش فایل دارد. همه با هدف «iPad Pro M5 با ۱۲ گیگابایت رم» و «نصب راحت نرم‌افزاری که apk نیست» ساخته شده‌اند. گزارش کامل: [`../docs/fa/linpad-m5-report.md`](../docs/fa/linpad-m5-report.md) (نسخه خوانا: [`linpad-m5-report.html`](../docs/fa/linpad-m5-report.html)).

| فایل | کجا اجرا می‌شود | نیاز به build دوباره؟ |
|---|---|---|
| `phase0.sh` | داخل لینوکس LinPad، با کاربر root | نه |
| `linpad-shelf` | داخل لینوکس LinPad، با کاربر root | نه |
| `m5-tune.sh` | داخل لینوکس LinPad، با کاربر root | نه |
| `linpad-get` | داخل لینوکس LinPad، با کاربر root | نه |
| `app-m5.patch` | روی مک، داخل کلون پروژه | بله (یک‌بار build) |
| همین README | — | — |

---

## ۰. شروع از اینجا: فاز ۰ با یک دستور

`phase0.sh` همان «فاز ۰» گزارش است: اندازه‌گیری وضع فعلی، اعمال پروفایل ۱۲ گیگابایتی، و بعد نشان‌دادن سه تنظیمی که فقط با دست روی آیپد انجام می‌شوند. دو فایل `phase0.sh` و `m5-tune.sh` را با هم در یک پوشه بگذارید.

```sh
sh phase0.sh            # اندازه‌گیری پایه + اعمال پروفایل + یادآوری تنظیمات
sh phase0.sh --check    # وضعیت فعلی، بدون تغییر
sh phase0.sh --after    # بعد از یک روز استفاده: مقایسه با پایه
sh phase0.sh --undo     # برگشت
```

پنج عددی که اندازه می‌گیرد و در `/root/linpad-perf/` ذخیره می‌کند: حافظهٔ مصرفی و سقف، سرعت حلقهٔ ۲۰۰ هزارتایی شل، حلقهٔ ۱۰۰ میلیونی Node، و درصد CPU بی‌کار. اگر بعد از تغییری این اعداد بدتر شدند، تغییر را بردارید.

سه تنظیمی که خودتان باید بزنید (اسکریپت یادآوری می‌کند):

1. `Settings › Fast Mode › Code cache` → **۵۱۲ MB** (بعدش اپ را کامل ببندید و باز کنید)
2. `Settings › Desktop › Performance overlay` → **روشن**
3. `Settings › Memory › Never close` → `code, firefox-esr`

---

## ۰٫۵ فایرفاکس ۱۵۳ — حالا از داخل اپ

دیگر اسکریپت دستی لازم نیست. در دسکتاپ **Debian Shelf** را باز کن؛ اگر فایرفاکس نصب نباشد، کارت **Install Firefox 153** را میبینی. یک کلیک:

- نسخهٔ ۱۲۸ (بدون وصلهٔ امنیتی) حذف میشود،
- آخرین `firefox-esr` دبیان نصب میشود،
- پروفایل تازهٔ بهینه ساخته میشود،
- و کلیک روی لینک در اپهای لینوکسی به آن میرود.

ابزارهای مهمان (`linpad-shelf`، `linpad-get`، `m5-tune.sh`) هم اولین بار که این پنجره باز شود، **خودِ اپ** داخل لینوکس مینویسد — بدون ترمینال.

---
## ۰٫۷ فاز ۲ — قفسهٔ قرنطینه (`linpad-shelf`)

ابزار اصلی فاز ۲. هر اپ دبیان را در پوشهٔ خودش نصب می‌کند، از یک **runtime مشترک** استفاده می‌کند و **هیچ فایلی در `/usr/lib`، `/lib` یا `/usr/bin` نمی‌نویسد**.

```sh
sh linpad-shelf doctor                         # محیط، runtime، اپ‌ها
sh linpad-shelf install keepassxc              # بستهٔ دبیان با نام
sh linpad-shelf install ./signal_arm64.deb     # فایل
sh linpad-shelf install https://…/app.deb      # لینک
sh linpad-shelf list
sh linpad-shelf verify                         # همهٔ کتابخانه‌ها resolve می‌شوند؟
sh linpad-shelf remove keepassxc               # پاک‌کردن کامل
```

| مسیر | چیست |
|---|---|
| `/usr/lib/linpad-shelf/runtime/` | runtime مشترک glibc (یک‌بار ساخته می‌شود، مشترک بین همهٔ اپ‌ها) |
| `/opt/linpad-shelf/<name>/root/` | پیلود اپ — تنها جایی که اپ زندگی می‌کند |
| `/opt/linpad-shelf/<name>/lib/` | کتابخانه‌های خصوصی خود اپ (اگر داشته باشد) |
| `/usr/local/bin/<name>` | لانچر تولیدشده |
| `/var/lib/linpad-shelf/<name>/` | دفتر ثبت برای حذف دقیق |

**سه چیزی که خودکار تصمیم‌گیری می‌شود:** اگر اپ Electron باشد `--no-sandbox` و Wayland می‌گیرد؛ اگر Qt باشد `QT_QPA_PLATFORM=wayland`؛ داده‌هایش از `XDG_DATA_DIRS` داخل overlay خوانده می‌شود (نه با کپی در `/usr/share`). برای اپ‌های لجباز `--system-data` هست و برای X11-onlyها `--x11`.

**نکتهٔ فایرفاکس:** `firefox-esr` در `trixie/main` نیست (در `trixie-security` است)، پس با نام نصب نمی‌شود. برای نسخهٔ ۱۵۳ از کارت **Install Firefox 153** در همین پنجره استفاده کن.

**اولین اجرا:** ساخت runtime حدود ۲۰۰–۳۰۰ مگابایت دانلود دارد و یک‌بار است. هیچ سرویس یا autostart اضافه نمی‌شود، پس روی بوت و CPU بی‌کار اثری ندارد.

---

## ۰٫۸ فاز ۳ — فایرفاکس داخل قفسه و پیش‌فرض

```sh
sh linpad-shelf migrate-firefox
```

این دستور سه کار می‌کند:

1. **اگر فاز ۱ را اجرا کرده باشید**، همان نصب `/opt/firefox-esr` را **بدون دانلود دوباره** به قفسه منتقل می‌کند (پیلود به `/opt/linpad-shelf/firefox-esr/root`، لانچر و `.desktop` بازنویسی می‌شوند، پروفایل دست‌نخورده می‌ماند).
2. **اگر فاز ۱ را اجرا نکرده باشید**، آخرین `firefox-esr` را از ایندکس امنیتی دبیان پیدا و نصب می‌کند.
3. **نسخهٔ ۱۲۸ را کاملاً حذف می‌کند** — بسته، فایل‌های `/usr/lib/firefox-esr`، و ورودی دسکتاپ قدیمی. پروفایل قدیمی `/root/.mozilla` عمداً می‌ماند.

قوانین خودکار فایرفاکس در قفسه:

- نام لانچر همیشه `firefox-esr` است، تا `ish-open` (کلیک روی لینک در اپ‌های لینوکسی) و `$BROWSER` خودکار آن را پیدا کنند.
- پروفایل تازه در `~/.mozilla-firefox-esr153` با `user.js` بهینه؛ اگر از قبل باشد، دست نمی‌خورد.
- `MOZ_ENABLE_WAYLAND=1` و `MOZ_DISABLE_CONTENT_SANDBOX=1` در لانچر.
- خط `firefox-esr 2 1` در `/etc/ishwl/app-scale` (متن تیز در حالت عادی، نصف پیکسل‌ها در fullscreen).

**پیش‌فرض شدن بدون مک:** کلید `desktop.linux.urlHandler` در اپ هیچ رابط کاربری ندارد و فقط با build عوض می‌شود. به‌جایش، `migrate-firefox` فایل `/usr/local/bin/ish-open` را (که اپ لینوکسی برای باز کردن لینک استفاده می‌کند) با یک نسخهٔ نازک جایگزین می‌کند که مستقیم فایرفاکس را صدا می‌زند. نسخهٔ اصلی در `/var/lib/linpad-shelf/ish-open.orig` بکاپ می‌شود و با `remove firefox-esr` خودکار برمی‌گردد. نتیجه: کلیک روی لینک در foot، VS Code و هر اپ لینوکسی، فایرفاکس ۱۵۳ را باز می‌کند — نه Quick Preview را.

**برگشت:**

```sh
sh linpad-shelf remove firefox-esr    # قفسه را پاک می‌کند، پروفایل می‌ماند
apk add firefox-esr                   # اگر نسخهٔ ۱۲۸ را برگرداند
```

---

## ۰٫۹ فاز ۴ — پنجرهٔ «Debian Shelf» در دسکتاپ

دو تکه دارد:

**الف) سمت مهمان (همین حالا قابل تست):** دستور `linpad-shelf list --json` خروجی ماشین‌خوان می‌دهد:

```sh
sh linpad-shelf list --json
# {"apps":[{"name":"keepassxc","version":"2.7.9-1","size":"182M","source":"debian:keepassxc"}]}
```

**ب) سمت اپ (نیازمند build):** فایل `desktop/DesktopKit/Sources/DesktopKit/Apps/Shelf/ShelfApp.swift` — پنجره‌ای با کادر «Install from a link»، فهرست اپ‌های نصب‌شده، دکمهٔ Open/Remove و پنل Log. در `BuiltinApps` و `AppID` ثبت شده است.

⚠️ این فایل Swift روی ویندوز **کامپایل نشده**؛ برای دیدنش در اپ باید روی مک با Xcode build بگیرید. تا آن موقع، همان قابلیت از ترمینال با `linpad-shelf install <link>` کار می‌کند.

---

## ۱. `m5-tune.sh` — پروفایل حافظه برای ۱۲ گیگابایت

LinPad برای iPad Air M3 با ۸ گیگابایت تنظیم شده: یک پروسه Firefox، کش کوچک، دو arena برای glibc. این اسکریپت آن‌ها را برای ۱۲ گیگابایت باز می‌کند و کاملاً برگشت‌پذیر است.

```sh
sh m5-tune.sh --status    # چه چیزی الان اعمال است
sh m5-tune.sh             # اعمال
sh m5-tune.sh --undo      # برگشت
```

بعد از اعمال، یک‌بار **Lock Screen › Restart Desktop Session** (یا بستن و باز کردن LinPad) لازم است.

چه فایل‌هایی را دست می‌زند:

- `/etc/ishwl/session.d/25-m5.sh` — `MALLOC_ARENA_MAX=6`، `NODE_OPTIONS=--max-old-space-size=4096`
- `/etc/profile.d/99-linpad-m5.sh` — همان `NODE_OPTIONS` برای شل‌های login
- یک بلوک مشخص در `/usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js`

از فایل‌های موجود نسخه پشتیبان در `/var/lib/linpad/m5-profile` می‌گیرد و `--undo` همان‌ها را برمی‌گرداند.

**نکته:** مقدار `MALLOC_ARENA_MAX` عمداً بی‌قید نوشته شده. فایل `15-lowmem.sh` که قبل از این اجرا می‌شود، مقدار را روی ۲ می‌گذارد؛ اگر این‌جا از `${MALLOC_ARENA_MAX:-6}` استفاده می‌کردیم هیچ اثری نداشت.

---

## ۲. `linpad-get` — نصب `.deb`، AppImage، tarball و rpm

مخزن LinPad فقط بسته‌های Alpine را می‌شناسد. این ابزار فرمت‌های دیگر را هم نصب می‌کند — روی نسخه ۱٫۵٫۰ که همین حالا نصب می‌کنید، بدون build دوباره.

### نصب کردن ابزار

فایل را به یکی از این دو روش داخل مهمان ببرید:

```sh
# الف) اگر جایی منتشرش کردید (GitHub raw، سرور خودتان…)
curl -fL -o /usr/local/bin/linpad-get https://…/linpad-get
chmod 755 /usr/local/bin/linpad-get

# ب) یا از Files: فایل را در پوشه Downloads آیپد بگذارید، بعد در ترمینال
cp /root/Downloads/linpad-get /usr/local/bin/ && chmod 755 /usr/local/bin/linpad-get
```

### استفاده

```sh
linpad-get doctor                       # اول این: چه چیزی هست، چه چیزی نیست
linpad-get install gimp                 # بسته apk (مثل apk add)
linpad-get install ./app.deb            # بسته Debian aarch64
linpad-get install https://…/app.deb    # دانلود و نصب
linpad-get install ./App.AppImage       # بدون FUSE باز و نصب می‌شود
linpad-get install ./tool.tar.xz
linpad-get remove <name>
linpad-get list
```

### چند نکته که باید بدانید

- **فقط aarch64.** باینری x86_64 اجرا نمی‌شود؛ نه این ابزار، نه LinPad.
- **اولین نصب glibc طولانی است.** «جزیره glibc» (کتابخانه‌های Debian) یک‌بار ساخته می‌شود: چند صد مگابایت دانلود. اگر VS Code یا Wine را نصب کرده باشید، از همان استفاده می‌کند و چیزی دانلود نمی‌شود.
- **فایل‌های apk بازنویسی نمی‌شوند.** هر مسیری که مال یک بسته apk باشد (با `apk info -W`) رد می‌شود. همین محافظ جلوی خراب شدن libc و داده‌های XKB را می‌گیرد.
- **لانچر بعد از نصب ظاهر نمی‌شود** تا سشن ری‌استارت شود — این محدودیت خود LinPad است، نه این ابزار.
- **حتماً اول backup بگیرید:** `Settings › Maintenance › Backup`.

### اگر کتابخانه کم آورد

پیام `still needs: libfoo.so.1` یعنی آن کتابخانه در جزیره نیست. دو راه:

```sh
# ۱) ببینید کدام بسته Debian آن را دارد، بعد بسته را به BASE_LIBS در خود اسکریپت اضافه کنید
# ۲) یا موقتاً کتابخانه را از همان .deb استخراج و در جزیره بگذارید
```

---

## ۳. `app-m5.patch` — پچ سمت اپ (اعمال‌شده در این کپی)

سه تغییر کوچک:

۱. `app/iSH.entitlements` — افزودن `com.apple.developer.kernel.increased-memory-limit`
۲. `desktop/…/Core/System/FastMode.swift` — گزینه‌های ۷۶۸ و ۱۰۲۴ مگابایت برای کش کد
۳. `app/AppDelegate.m` — فعال‌کردن swapfile فشاری (`ISH_SWAPFILE=pressure`) روی دستگاه‌های ≥ ۶ گیگابایت

```sh
git apply --check personalize/app-m5.patch
git apply -R personalize/app-m5.patch     # برگرداندن
```

**اگر امضا شکست خورد:** پنج خط مربوط به entitlement را از `app/iSH.entitlements` بردارید. تیم توسعه‌دهنده رایگان همیشه آن را در پروفایل ندارد.

**swapfile آزمایشی است.** سورس خودش آن را «prototype for measuring» می‌نامد و در نسخه منتشرشده استفاده نشده. با `LINPAD_NO_SWAPFILE=1` خاموش می‌شود.

---

## ۴. ترتیب پیشنهادی کار

1. از مهم‌ترین چیزها backup بگیرید (`Settings › Maintenance › Backup`).
2. `linpad-get doctor` و بعد `linpad-get island` (یک‌بار).
3. `m5-tune.sh` و ری‌استارت سشن.
4. Code cache را روی ۵۱۲ بگذارید.
5. اگر مک دارید: پچ را بزنید و build کنید — بیشترین سود از entitlement حافظه است.
6. یک روز کار عادی با Performance overlay؛ اگر `phys_footprint` نزدیک سقف بود، سراغ گام ۵ بروید.
