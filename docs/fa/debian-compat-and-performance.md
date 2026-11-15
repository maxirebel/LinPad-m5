# پیشنهاد تغییرات برای سازگاری با اپ‌های دبیان و اجرای روان

> **دستگاه:** iPad Pro M5، ۱۲ گیگابایت، iPadOS 27.2 · **LinPad 1.5.0** (Alpine 3.21، musl)
> **مطالعهٔ موردی:** جایگزینی Firefox ESR 128.14 با نسخهٔ جدید دبیان
> **وضعیت:** فقط پیشنهاد و گزارش؛ چیزی اعمال نشده است.

---

## خلاصه اجرایی

سازگاری با اپ‌های دبیان دو مسئلهٔ جدا است که مردم با هم اشتباه می‌گیرند:

۱. **مسئلهٔ نصب** — «فایل `.deb` را چطور روی این سیستم بگذارم؟» این تقریباً حل شده است: جزیرهٔ glibc + `linpad-get` کار می‌کند.
۲. **مسئلهٔ یکپارچگی و روانی** — «چرا هر اپ جدید یک ماجرای دستی است، و چرا کند است؟» این حل نشده است، و دلیلش هم فایل `.deb` نیست.

پیشنهاد من در سه لایه، با ترتیب بازدهی:

| اولویت | تغییر | نوع | تخمین | اثر |
|---|---|---|---|---|
| **۱** | `pcache` را از ۴۸ مگابایت به ۲۵۶ مگابایت ببرید (مخصوص iPad) | ۲ خط C + یک تنظیم | ۲ ساعت | **بیشترین اثر روی سرعت اجرای مجدد Firefox/Node** |
| **۲** | تبدیل جزیرهٔ glibc به یک **مخزن apk** (`linpad-compat`) و بسته‌بندی اپ‌های دبیان به‌صورت پکیج | اسکریپت + CI | ۳–۵ روز | نصب/حذف/آپدیت با `apk`، دیده‌شدن در استور، حذف تمیز |
| **۳** | چند `prctl` ساده در هسته (`NO_NEW_PRIVS`، `PDEATHSIG`، `DUMPABLE`، `SUBREAPER`) | ۳۰ خط C | ۳–۴ ساعت | بخش بزرگی از اپ‌های sandbox‌دار بدون `--no-sandbox` بالا می‌آیند |
| ۴ | سقف JIT arena بر اساس `hw.memsize` (۵۱۲ مگابایت روی ≥۸ گیگ) | ۵ خط | ۱ ساعت | کمتر شدن ترجمهٔ تکراری در مرورگر |
| ۵ | resolver چندمنبعی دبیان (main + security + updates) | اسکریپت | ۱–۲ روز | بدون آن، بستهٔ امنیتی Firefox اصلاً پیدا نمی‌شود |
| ۶ | مهاجرت rootfs به Alpine 3.24 | build | ۱ روز | Firefox ESR 140.12 و Qt/GTK جدید، به‌صورت بومی |

قاعدهٔ کلی: **هرچه اپ را به بستهٔ Alpine نزدیک‌تر کنید، روان‌تر است.** جزیرهٔ glibc یک پل است، نه مقصد. اما برای اپ‌هایی که فقط `.deb` دارند، این پل باید «یک‌بار برای همیشه» ساخته شود، نه هر بار دستی.

---

## ۱. تشخیص: امروز چرا کند و ناسازگار است؟

چهار گلوگاه واقعی وجود دارد، و هیچ‌کدام «کم بودن رم» نیست:

### ۱٫۱ کش ترجمهٔ دائمی (pcache) برای این دستگاه کوچک تنظیم شده

در `jit/pcache.c:156-158` اندازهٔ پیش‌فرض **۴۸ مگابایت روی iOS** و ۱۲۸ مگابایت روی مک است. کامنت خود فایل می‌گوید این کش برای این است که «node، claude، Firefox و شل سریع‌تر بالا بیایند، چون `libxul` و `libnode` دوباره ترجمه نمی‌شوند».

اما `libxul` تنها در پروسهٔ اصلی حدود **۱۸۰ مگابایت** ترجمه می‌خواهد (کامنت `jit/codemem.c:216-217`). یعنی کش ۴۸ مگابایتی تقریباً بلافاصله پر می‌شود و از نو شروع می‌کند. روی یک دستگاه ۱۲ گیگی با ۱۵۳ گیگابایت‌بر‌ثانیه پهنای باند، این عدد بی‌معنی است.

### ۱٫۲ سقف JIT بر اساس حافظهٔ آزاد لحظهٔ شروع

`jit/codemem.c:221` می‌گوید اگر بیش از ۳ گیگابایت آزاد باشد، ۲۵۶ مگابایت بردار. روی M5/۱۲GB این تقریباً همیشه ۲۵۶ می‌شود — یعنی گزینهٔ «automatic» عملاً همان ۲۵۶ است، در حالی که اپ تا ۱۰۲۴ را قبول می‌کند (`AppDelegate.m:242-246`).

### ۱٫۳ sandbox: نه seccomp، نه userns — و `prctl` ناقص

`kernel/misc.c:7-26` فقط دو `prctl` را می‌شناسد: `PR_SET_KEEPCAPS` و `PR_SET_NAME`. بقیه با `EINVAL` برمی‌گردند. این یعنی:

- `PR_SET_NO_NEW_PRIVS` شکست می‌خورد → Chromium/Firefox/Electron نمی‌توانند sandbox را راه بیندازند و یا کرش می‌کنند یا مجبورید `--no-sandbox` بدهید.
- `PR_SET_PDEATHSIG` شکست می‌خورد → بعضی helperها بعد از مرگ والد یتیم می‌مانند.
- `PR_SET_DUMPABLE` / `PR_SET_CHILD_SUBREAPER` → رفتارهای فرعی عجیب.

این تنها یکی از دلایلی است که اپ‌های Electron روی این سیستم «کار می‌کنند ولی با پرچم» — و همان چیزی است که با ۳۰ خط C قابل بهبود است.

### ۱٫۴ داده‌ها، نه باینری‌ها

اپ دبیان فقط کتابخانه نمی‌خواهد: اسکیمای GSettings، فایل‌های MIME، آیکون‌ها، فونت‌ها، `systemd` unit (که نداریم) و گاهی helperهای `libexec`. اگر این‌ها نصب نشوند، اپ «اجرا می‌شود ولی صفحهٔ سفید/خطای schema» می‌دهد. `linpad-get` فعلی پیلود کامل `.deb` را می‌ریزد، پس این را پوشش می‌دهد — ولی `debfetch` که فقط `lib*` را دنبال می‌کند، نه.

---

## ۲. پیشنهاد اصلی: «لایهٔ سازگاری دبیان» به‌عنوان یک قابلیت، نه یک اسکریپت

### ۲٫۱ تصویر کلی

```
        ┌──────────────────────────────────────────────┐
        │  Store (Swift)  ──  ایندکس دوم: compat       │
        └───────────────┬──────────────────────────────┘
                        │  apk add linpad-app-firefox-esr
        ┌───────────────▼──────────────────────────────┐
        │  مخزن apk:  linpad-compat (aarch64)          │
        │   • linpad-runtime-glibc  (جزیره، نسخه‌دار)  │
        │   • linpad-app-<name>     (اپ تبدیل‌شده)     │
        └───────────────┬──────────────────────────────┘
                        │  نصب/حذف/آپدیت توسط apk
        ┌───────────────▼──────────────────────────────┐
        │  /opt/linpad-apps/<name>/  +  wrapper + .desktop │
        └──────────────────────────────────────────────┘
```

چرا **apk** و نه یک نصب‌کنندهٔ اختصاصی؟

- `apk` از قبل مالک فایل‌ها، وابستگی‌ها، نسخه‌ها و حذف تمیز است — چیزی که `linpad-get` دستی انجام می‌دهد و همیشه ناقص می‌ماند.
- استور همین حالا بسته‌های apk را می‌فهمد (`linpad-apps` + `store-index.json`)؛ با یک مخزن جدید، **بدون تغییر معماری** اپ‌های دبیان هم در استور ظاهر می‌شوند.
- `apk upgrade` همه‌چیز را با هم به‌روز می‌کند، از جمله اپ‌های دبیان.

### ۲٫۲ پنج قطعهٔ لازم

| قطعه | کار | جایی که وصل می‌شود |
|---|---|---|
| **الف) `linpad-runtime-glibc`** | جزیرهٔ glibc را به یک بستهٔ apk نسخه‌دار تبدیل می‌کند (`/usr/lib/aarch64-linux-gnu` + لودر + `Depends` روی libs) | `devtools/install-vscode.sh` فعلی، تعمیم‌یافته |
| **ب) `deb2apk`** | یک `.deb` (و closure وابستگی‌هایش) را به یک apk با `Depends: linpad-runtime-glibc` تبدیل می‌کند | ابزار جدید در `tools/` |
| **ج) resolver چندمنبعی** | `Packages.xz` را از `trixie/main`، `trixie-security` و `trixie-updates` می‌خواند و وابستگی‌ها را با blocklist حل می‌کند | ارتقای `devtools/debfetch.mjs` |
| **د) policy engine** | برای هر اپ تصمیم می‌گیرد: `--no-sandbox`؟ `MOZ_DISABLE_CONTENT_SANDBOX`؟ X11 rule؟ کدام prefs؟ | فایل `policy.json` + مولد wrapper |
| **هـ) ایندکس استور** | `linpad-compat-index.json` با `kind: "compat"`، وضعیت سازگاری و حجم | `linpad-store-index.mjs` |

### ۲٫۳ چرا resolver فعلی کافی نیست — و چطور درستش کنیم

`debfetch.mjs` امروز:

- فقط `lib*` را دنبال می‌کند (`isLibraryPackage`)، پس `libavcodec61` (که برای پخش H.264 لازم است) اگر به‌عنوان Recommends باشد نمی‌آید.
- فقط یک suite/mirror می‌شناسد (`--suite trixie`)، پس **Firefox 153.7 که در `trixie-security` است پیدا نمی‌شود** — این را با تست واقعی تأیید کردم: `firefox-esr` در trixie/main نیست، در `security.debian.org/debian-security` است.
- `Recommends` را نمی‌خواند، در حالی که برای مرورگر و Qt تقریباً همیشه لازم است.

پیشنهاد دقیق:

```js
// ورودی: [{suite:'trixie', mirror:'https://deb.debian.org/debian'},
//         {suite:'trixie-security', mirror:'https://security.debian.org/debian-security'}]
// خروجی: انتخاب نسخهٔ بالاتر، دنبال‌کردن Depends + Recommends با blocklist
const BLOCK = ['systemd','systemd-sysv','udev','initramfs-tools','dbus-daemon',
               'libpam-systemd','policykit-1','snapd','apparmor'];
```

و یک نکتهٔ مهم: `debfetch` الان `roots` را (اپ) هم دانلود می‌کند و فقط وابستگی‌هایش را فیلتر می‌کند. یعنی **همین ابزار می‌تواند کل اپ + کتابخانه‌هایش را در یک prefix بریزد**. این پایهٔ `deb2apk` است.

### ۲٫۴ قرارداد هر بستهٔ compat

```
/opt/linpad-apps/<name>/app/…            # پیلود .deb
/opt/linpad-apps/<name>/lib/…            # فقط اگر نسخهٔ خصوصی لازم است
/usr/local/bin/<name>                    # wrapper با unset + پرچم‌ها
/usr/share/applications/<name>.desktop
/etc/ishwl/apps                          # اگر X11 لازم است
/var/lib/linpad-apps/<name>.json         # منبع، نسخهٔ دبیان، تاریخ
```

`Depends: linpad-runtime-glibc (= 2026.11)` تضمین می‌کند جزیره همیشه قبل از اپ نصب شود و با آپدیت اپ، سازگار بماند.

### ۲٫۵ policy engine — قلب «روانی»

برای هر اپ، این تصمیم‌ها باید **خودکار** باشند، نه دستی:

| نشانه | تصمیم |
|---|---|
| `resources/app.asar` یا `chrome-sandbox` وجود دارد | Electron → `--no-sandbox` + `ELECTRON_OZONE_PLATFORM_HINT=wayland` |
| نام باینری `firefox*` | `MOZ_ENABLE_WAYLAND=1`، `security.sandbox.content.level=0`، prefs فایرفاکس |
| لینک به `libQt6Core` دارد | `QT_QPA_PLATFORM=wayland`؛ اگر پلاگین QtWayland نبود → هشدار «Qt runtime لازم است» |
| `.desktop` می‌گوید `Exec=… x11` یا باینری `libX11` دارد | قاعدهٔ `x11` در `/etc/ishwl/apps` |
| بسته `glib-2.0/schemas/*.xml` دارد | `glib-compile-schemas` در post-install |
| بسته فونت/آیکون دارد | `ish-apply-style --cache-only` |

این جدول همان چیزی است که امروز در مغز شما و در README من است؛ باید در کد باشد.

### ۲٫۶ استور و ماتریس تست

مشکل فعلی: ۷۷۱ اپ از ۸۰۰ «Not tested» هستند. برای compat هم همین اتفاق می‌افتد اگر تست خودکار نباشد.

پیشنهاد: یک harness در CI که هر بستهٔ compat را در emulator بالا می‌آورد (`ishwl` headless)، ۱۵ ثانیه صبر می‌کند، اسکرین‌شات می‌گیرد و سه وضعیت می‌دهد: `launches` / `crashes` / `no-window`. همان کاری که پروژه برای پک‌ها دستی کرده (`release/CHECKLIST.md`، جدول پک‌ها). خروجی این harness، فیلد `compat` در ایندکس است.

---

## ۳. تغییرات کوچک هسته که سازگاری را جهش می‌دهد

### ۳٫۱ `prctl` — ۳۰ خط، بزرگ‌ترین برد

`kernel/misc.c` را این‌طور گسترش دهید (مقادیر ثابت لینوکس):

| option | مقدار | رفتار پیشنهادی |
|---|---|---|
| `PR_SET_PDEATHSIG` | ۱ | ذخیره در task؛ در `exit` سیگنال بفرست (یا حداقل ۰ برگردان) |
| `PR_SET_DUMPABLE` | ۴ | ۰ برگردان |
| `PR_GET_DUMPABLE` | ۳ | ۱ برگردان |
| `PR_SET_TIMERSLACK` | ۲۹ | ۰ |
| `PR_SET_CHILD_SUBREAPER` | ۳۶ | ۰ |
| `PR_SET_NO_NEW_PRIVS` | ۳۸ | ۰ (فقط اگر setuid باینری‌ها را جدی نمی‌گیرید) |
| `PR_GET_NO_NEW_PRIVS` | ۳۹ | ۱ |
| `PR_SET_VMA` | ۸۰ | ۰ |

اثر: Chromium/Electron/Firefox بدون پرچم `--no-sandbox` هم ممکن است بالا بیایند (چون حداقل `NO_NEW_PRIVS` موفق می‌شود)، و برنامه‌هایی که `PDEATHSIG` می‌خواهند درست کار می‌کنند.

### ۳٫۲ `seccomp` — با احتیاط

`syscall(SYS_seccomp, …)` امروز `ENOSYS` است. دو گزینه:

- **محافظه‌کارانه (پیشنهاد من):** همان `ENOSYS` بماند؛ اکثر برنامه‌ها fallback دارند و کرش نمی‌کنند.
- **پراگماتیک:** `SECCOMP_SET_MODE_FILTER` را قبول کن و فیلتر را نادیده بگیر (۰ برگردان). اپ‌های سخت‌گیر بالا می‌آیند، ولی **sandbox واقعی وجود ندارد** و این یک ریسک امنیتی است. اگر این کار را کردید، حتماً در UI اعلام کنید.

### ۳٫۳ `/proc` — فیلدهایی که برنامه‌ها می‌خوانند

- `/proc/self/status`: `NoNewPrivs`، `Seccomp`، `CapEff` را اضافه کنید تا ابزارهایی که وضعیت sandbox را چک می‌کنند گمراه نشوند.
- `/proc/sys/vm/overcommit_memory` و `/proc/sys/kernel/*` را با مقادیر ثابت پاسخ دهید (بعضی اپ‌ها موقع شروع می‌خوانند).
- `/proc/cpuinfo` باید `Features` معقول داشته باشد (NEON/ASIMD) — امروز دارد.

### ۳٫۴ فراخوان‌های جدید glibc

`faccessat2`، `statx`، `clone3`، `pidfd_open` اگر نیستند، بهتر است `ENOSYS` برگردانند (نه `EINVAL`) تا glibc به مسیر قدیمی fallback کند. این یک قاعدهٔ کلی است: **`ENOSYS` یعنی «این را ندارم، راه دیگری برو»؛ `EINVAL` یعنی «درخواستت غلط است» و بعضی کتابخانه‌ها را متوقف می‌کند.**

---

## ۴. پیشنهادهای عملکردی (به ترتیب بازدهی)

### ۴٫۱ pcache: ۴۸ → ۲۵۶ مگابایت

| کجا | تغییر |
|---|---|
| `jit/pcache.c:156-158` | `def_mb = 256` روی iOS (یا بر اساس `hw.memsize`) |
| `app/AppDelegate.m` | `setenv("ISH_JIT_PCACHE_MB", …)` از یک تنظیم جدید |
| `FastMode.swift` | افزودن گزینهٔ «Persistent cache» با مقادیر ۴۸/۱۲۸/۲۵۶/۵۱۲ |

سود: اجرای دوم به بعد Firefox/Node/Claude Code به‌طور محسوس سریع‌تر؛ هزینه: تا ۲۵۶ مگابایت از حافظهٔ سقف jetsam (روی ۱۲ گیگابایت ناچیز) و مقداری نوشتن روی SSD در هر خروج پروسه.

### ۴٫۲ JIT arena بر اساس سخت‌افزار، نه حافظهٔ لحظهٔ boot

```c
// به‌جای avail > 3GB ? 256MB : ...
uint64_t ram = 0; size_t sz = sizeof(ram);
sysctlbyname("hw.memsize", &ram, &sz, NULL, 0);
arena_size = ram >= (8ull << 30) ? 512u << 20 : avail > (3ull << 30) ? 256u << 20 : ...
```

### ۴٫۳ پروفایل Firefox (هم برای نسخهٔ Alpine و هم دبیان)

مقادیر کلیدی که امروز در `release/guest/gecko-tune.sh` هست، برای نسخهٔ دبیان هم باید اعمال شود:

- `dom.ipc.processCount=1` و `fission.autostart=false` — هر پروسهٔ اضافه یک کپی کامل ترجمهٔ `libxul` می‌خواهد.
- `layout.css.stylo-threads=2` — هر ترد مهمان حدود ۱٫۳ مگابایت هزینهٔ میزبان دارد (`kernel/oom.c:30`).
- `media.mediasource.webm.enabled=false` و `media.av1.enabled=false` — H.264 ارزان‌تر است (اعداد در همان فایل).
- `browser.low_commit_space_threshold_percent=20` و `tabs.unloadOnLowMemory=true`.
- برای نسخهٔ دبیان: `security.sandbox.content.level=0` و `MOZ_DISABLE_CONTENT_SANDBOX=1` (چون seccomp نیست).

### ۴٫۴ `MALLOC_ARENA_MAX` برای هر اپ glibc

پروفایل `m5-tune.sh` این را روی ۶ گذاشت (از ۲). برای Firefox دبیان هم مهم است چون jemalloc خودش را دارد ولی کتابخانه‌های اطراف از glibc malloc استفاده می‌کنند.

### ۴٫۵ GPU برای مرورگر — با چشم باز

مسیر GPU الان این است: Venus → virglrenderer → MoltenVK → Metal، و `ishwl` فقط `wl_shm` می‌پذیرد (`gpu/DESIGN.md`). یعنی حتی اگر Firefox با zink رندر کند، فریم آخر با CPU کپی می‌شود. برای صفحهٔ معمولی سودی ندارد؛ برای ویدیوی بزرگ و اسکرول سنگین ممکن است چند فریم بدهد. **اولویت پایین** تا وقتی dma-buf در ishwl پیاده شود.

### ۴٫۶ مقیاس نمایش

`/etc/ishwl/app-scale` را برای اپ‌های سنگین روی ۱ بگذارید (نصف پیکسل‌ها = نصف کار رندر). برای Firefox می‌توانید ۲ در حالت عادی و ۱ در fullscreen نگه دارید (همین الان پیش‌فرض است).

---

## ۵. مطالعهٔ موردی: جایگزینی Firefox

### ۵٫۱ وضعیت واقعی نسخه‌ها

از شاخص‌های واقعی مخازن (نه حدس):

| نسخه | از کجا | عدد |
|---|---|---|
| **نصب‌شده در LinPad** | Alpine 3.21 community | `firefox-esr 128.14.0-r0` |
| Firefox عادی در همان 3.21 | Alpine 3.21 community | `firefox 136.0.4-r0` |
| Alpine 3.24 | `firefox-esr 140.12.0` / `firefox 151.0.3` | جدیدتر، musl |
| **دبیان trixie (security)** | `firefox-esr 153.7.0esr-1~deb13u1` | جدیدترین، glibc، arm64 |
| حجم بستهٔ دبیان | ۷۰ مگابایت / نصب ۲۸۱ مگابایت | arm64 |

نکتهٔ مهم: `128.14` نسخهٔ ESR است که **پشتیبانی امنیتی‌اش تمام شده**؛ این تنها دلیل لازم برای ارتقاست، حتی اگر ظاهراً همه‌چیز کار کند.

### ۵٫۲ سه مسیر

| | مسیر A: Alpine 3.24 | مسیر B: دبیان 153.7 | مسیر C: Firefox 136 از 3.21 |
|---|---|---|---|
| نسخه | ESR 140.12 یا Release 151 | **ESR 153.7** | Release 136 |
| libc | musl (بومی) | glibc (جزیره) | musl |
| حجم اضافه | ~۰ | +۲۸۱MB اپ + ~۱۸۰MB کتابخانه | ~۰ |
| سرعت | بیشترین | کمی کمتر (لودر glibc + کتابخانه بیشتر) | بیشترین |
| sandbox | همان وضع فعلی | باید خاموش شود | همان وضع فعلی |
| زحمت | build روت‌فاس + تست | `linpad-get`/compat | `apk add firefox` |
| ریسک | متوسط (Mesa/Qt) | متوسط (پروفایل + sandbox) | کم |

**توصیهٔ من:** اگر «روان» اولویت است، مسیر A. اگر «جدیدترین نسخه» اولویت است، مسیر B — و در این حالت compat layer باید ساخته شود، وگرنه هر آپدیت یک ماجرای دستی است. مسیر C فقط یک مسکن است (۱۳۶ هم قدیمی است).

### ۵٫۳ مسیر B به‌صورت گام‌به‌گام (امروز، بدون ساخت لایه)

```sh
# ۱. ابزارها
apk add dpkg libarchive-tools xz zstd patchelf nodejs

# ۲. پکیج‌ها را از مخزن امنیتی دبیان بگیرید (نه trixie/main)
#    firefox-esr در trixie-security است
mkdir -p /opt/compat/firefox-esr && cd /var/cache
curl -fLO https://security.debian.org/debian-security/pool/updates/main/f/firefox-esr/firefox-esr_153.7.0esr-1~deb13u1_arm64.deb

# ۳. استخراج در یک prefix (نه در /)
dpkg-deb -x firefox-esr_153.7.0esr-1~deb13u1_arm64.deb /opt/compat/firefox-esr

# ۴. جزیرهٔ glibc را بسازید (اگر نیست)
linpad-get island

# ۵. اجرا با لودر دبیان
env -u LD_PRELOAD MOZ_ENABLE_WAYLAND=1 MOZ_DISABLE_CONTENT_SANDBOX=1 \
  /lib/ld-linux-aarch64.so.1 --library-path /usr/lib/aarch64-linux-gnu \
  /opt/compat/firefox-esr/usr/lib/firefox-esr/firefox-esr --no-remote
```

اگر خطای کتابخانه گرفتید:

```sh
env -u LD_PRELOAD /lib/ld-linux-aarch64.so.1 --list /opt/compat/firefox-esr/usr/lib/firefox-esr/firefox-esr | grep 'not found'
```

و بسته‌های گمشده را با `debfetch` اضافه کنید (فهرست موردنیاز Firefox از `Depends` خودش: `libevent-2.1-7t64`، `libvpx9`، `libx11-xcb1`، `libxcb-shm0`، `libcairo-gobject2`، `libffi8`، و برای ویدیو `libavcodec61`).

### ۵٫۴ چه چیزی می‌شکند و چطور

| نشانه | علت | راه‌حل |
|---|---|---|
| تب‌ها بلافاصله crash می‌کنند | sandbox محتوا (seccomp نیست) | `security.sandbox.content.level=0` در prefs یا `MOZ_DISABLE_CONTENT_SANDBOX=1` |
| «Your browser can't play this video» | نبود `libavcodec` | `libavcodec61` را به جزیره اضافه کنید |
| صفحهٔ سفید و بدون منو | نبود schema/آیکون | `glib-compile-schemas` + بررسی `/usr/share/glib-2.0/schemas` |
| پروفایل قدیمی باز نمی‌شود | ارتقای ۱۲۸ → ۱۵۳ یک‌طرفه است | قبلش از `~/.mozilla` بکاپ بگیرید |
| فونت فارسی بد | فونت‌های Alpine (Noto) استفاده می‌شوند | `font-noto-arabic` نصب باشد |

### ۵٫۵ مهاجرت پروفایل

```sh
cp -a /root/.mozilla /root/.mozilla-backup-$(date +%F)
# سپس Firefox جدید را با همان پروفایل اجرا کنید؛ ارتقا خودکار است و برگشت‌پذیر نیست
```

---

## ۶. نقشهٔ راه پیشنهادی

### فاز ۰ — همین امروز، بدون build (۲ ساعت)
- `m5-tune.sh` + کش ۵۱۲ + پروفایل Firefox.
- تصمیم بگیرید کدام مسیر Firefox را می‌خواهید (A یا B).

### فاز ۱ — تغییرات کوچک با بازدهی بالا (۱–۲ روز)
- `pcache` قابل‌تنظیم + پیش‌فرض ۲۵۶MB روی ≥۸GB.
- `arena` بر اساس `hw.memsize`.
- `prctl` stubs + تست چند اپ sandbox‌دار.

### فاز ۲ — compat layer واقعی (۱–۲ هفته)
- resolver چندمنبعی + `deb2apk` + مخزن `linpad-compat`.
- policy engine + wrapper/desktop خودکار.
- harness تست خودکار برای برچسب سازگاری.
- ایندکس دوم استور.

### فاز ۳ — پایهٔ بلندمدت (۱ ماه)
- مهاجرت rootfs به Alpine 3.24 (بسته‌های بومی جدیدتر).
- dma-buf در ishwl (برای GPU واقعی).
- seccomp/namespace اگر روزی خواستید Flatpak — که فعلاً منطقی نیست.

---

## ۷. ریسک‌ها و ملاحظات

| ریسک | توضیح | کاهش |
|---|---|---|
| بستهٔ apk ساختگی و امضا | مخزن compat باید کلید امضای خودش را داشته باشد و در `/etc/apk/keys` نصب شود | کلید جدا، مستند، قابل بازبینی |
| نگهداری نسخه‌ها | هر آپدیت دبیان یعنی بازسازی بسته | CI خودکار روی `trixie-security` |
| sandbox خاموش | امنیت کمتر در محیطی که همه‌چیز root است | اعلام در UI، فقط برای اپ‌های مشخص |
| حافظه | هر اپ compat یک prefix دارد؛ چند اپ Electron = چند صد مگابایت | `du` در ایندکس، هشدار حجم |
| pcache بزرگ | نوشتن روی SSD و مصرف حافظه | سقف ۲۵۶MB، پاک‌کردن خودکار |
| Alpine 3.21 EOL | پایهٔ ناامن | فاز ۳ |

---

## ۸. اگر فقط سه کار بتوانید بکنید

۱. **`pcache` را روی ۲۵۶ مگابایت بگذارید** — بیشترین اثر روی «روان بودن» با کمترین تغییر.
۲. **`prctl` را کامل کنید** — بزرگ‌ترین برد سازگاری؛ اپ‌های Electron و مرورگرها بدون پرچم بالا می‌آیند.
۳. **Firefox را از دبیان نصب کنید، ولی به‌عنوان یک بستهٔ compat، نه یک دستور دستی** — تا آپدیتش هم مثل بقیه باشد.

و یک توصیهٔ صادقانه: اگر هدف «مرورگر به‌روز و روان» است، بهترین ترکیب برای این دستگاه **Firefox بومی Alpine 3.24 (ESR 140)** است با pcache بزرگ؛ نسخهٔ دبیان ۱۵۳ جدیدتر است، ولی به‌خاطر glibc و sandbox، در عمل روان‌تر نخواهد بود — فقط به‌روزتر است. اگر با این تفاوت راحت هستید، مسیر B درست است و باید compat layer را جدی ساخت.

---

## پیوست — فایل‌هایی که این تغییرات را لمس می‌کنند

`jit/pcache.c` · `jit/codemem.c` · `kernel/misc.c` · `kernel/fs.c` · `kernel/fork.c` · `app/AppDelegate.m` · `desktop/DesktopKit/Sources/DesktopKit/Core/System/FastMode.swift` · `devtools/debfetch.mjs` · `release/guest/gecko-tune.sh` · `release/guest/linpad/linpad-apps` · `release/guest/linpad/store/linpad-store-index.mjs` · `fs/mount.c`
