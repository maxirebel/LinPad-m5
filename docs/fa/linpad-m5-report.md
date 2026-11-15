# LinPad روی iPad Pro M5 (۱۲ گیگابایت)

## بررسی، شخصی‌سازی و مسیر «نصب آسان هر نرم‌افزار لینوکسی»

| | |
|---|---|
| **نسخه بررسی‌شده** | LinPad 1.5.0 (منتشرشده ۲۰۲۶-۱۰-۰۳) — [github.com/fspecii/LinPad](https://github.com/fspecii/LinPad) |
| **تاریخ گزارش** | ۱۴ نوامبر ۲۰۲۶ |
| **هدف سخت‌افزاری** | iPad Pro M5، مدل ۲۵۶ یا ۵۱۲ گیگابایت (۱۲ گیگابایت رم، CPU ۹ هسته‌ای، GPU ۱۰ هسته‌ای) |
| **سیستم‌عامل** | iPadOS 27.2 |

---

## خلاصه اجرایی

۱. **پروژه واقعی و جدی است، نه یک دموی تبلیغاتی.** ۲٫۴۴۸ فایل، ۳۴ مگابایت سورس C/Objective-C/Swift، شبیه‌ساز syscall لینوکس با JIT بومی ARM64، یک کامپوزیتور Wayland داخل مهمان، و یک دسکتاپ SwiftUI. اعداد داخل مخزن با ادعاهای README هم‌خوان است (system image فشرده ۵۸۹ مبی‌بایت / ۲٫۲۴ گیگابایت بازشده / ۲۱۶٬۹۵۲ فایل).

۲. **روی M5 راحت‌تر از M3 کار می‌کند، اما نه به‌خاطر رم بیشتر به‌تنهایی.** گلوگاه اصلی، «سقف حافظه هر اپ» در iPadOS (jetsam) است، نه سخت‌افزار. اپ به‌طور پیش‌فرض entitlement مربوط به افزایش سقف حافظه را ندارد؛ افزودن آن بزرگ‌ترین بردِ تک‌خطی این پروژه برای شماست.

۳. **مهم‌ترین مشکل پروژه دقیقاً همان چیزی است که شما گفته‌اید: توزیع نرم‌افزار.** استور پروژه ۸۰۰ اپ دارد (۷۸۰ بسته apk + ۲۰ پک)، ولی فقط ۲۹ مورد «تست‌شده» برچسب خورده‌اند. هر چیزی که apk نباشد — `.deb`، AppImage، بسته‌های glibc، نرم‌افزارهای x86_64 — امروز مسیر نصب ندارد.

۴. **چهار دیوار واقعی وجود دارد که با هیچ ترفند نصبی برداشته نمی‌شوند:** معماری (فقط aarch64)، libc (musl در برابر glibc)، نبود namespace و FUSE، و نبود systemd. Flatpak و Snap و Docker روی این معماری **ممکن نیستند**؛ نه اینکه سخت باشد — سازوکار هسته‌ای‌شان وجود ندارد.

۵. **بخش بزرگی از آنچه عملاً «نرم‌افزار لینوکسی aarch64» منتشر می‌شود، با سه قطعه نصب‌شدنی می‌شود:** یک نصب‌کننده `.deb`، یک بازکننده AppImage بدون FUSE، و یک «جزیره glibc» عمومی. (تخمین من از پوشش: نیمی تا دوسوم اپ‌های دسکتاپ رایج؛ نه همه — دیوارهای بخش ۴ سر جای خود هستند.) هر سه در همین گزارش ساخته و تحویل داده شده‌اند (`personalize/linpad-get`) و **بدون نیاز به build دوباره اپ** روی نسخه ۱٫۵٫۰ کار می‌کنند.

۶. **برای بهینه‌سازی M5/۱۲GB سه لایه وجود دارد:** تنظیمات بدون بیلد (اسکریپت `m5-tune.sh`)، یک پچ کوچک روی اپ (`personalize/app-m5.patch` — همان اعمال شده)، و بازسازی system image روی Alpine 3.24 (نیازمند مک).

۷. **یک هشدار فوری:** system image پروژه روی **Alpine 3.21** است و این شاخه در **۱ نوامبر ۲۰۲۶ EOL شد**. یعنی از دو هفته پیش هیچ وصله امنیتی برای مهمان منتشر نمی‌شود. مهاجرت به 3.23/3.24 یک بهینه‌سازی لوکس نیست؛ یک مسئله امنیتی است.

۸. **محدودیت‌های نصب اپ روی آیپد را جدی بگیرید:** با Apple ID رایگان، هر اپ بعد از ۷ روز منقضی می‌شود و هم‌زمان فقط ۳ اپ نصب می‌ماند؛ StikDebug و LocalDevVPN هم خودشان اپ سایدلودشده‌اند و همین قاعده را دارند. JIT هم بدون StikDebug روشن نمی‌شود.

---

## ۱. این پروژه چیست و چقدر از ادعاهایش واقعی است

### ۱.۱ معماری در یک نگاه

LinPad یک ماشین مجازی نیست و jailbreak نمی‌خواهد؛ **یک پروسه iOS** است که پنج لایه دارد:

| لایه | چیست | جایی که باید نگاه کنید |
|---|---|---|
| شبیه‌ساز | fork از iSH / iSH-ARM64: فراخوان‌های سیستمی لینوکس را به iOS ترجمه می‌کند و کد ARM64 مهمان را با JIT بومی اجرا می‌کند | `kernel/`, `jit/`, `emu/`, `asbestos/` |
| هسته مهمان | پیاده‌سازی syscallها: `kernel/` با ۵۹ فایل — `fork.c`, `mmap.c`, `signal.c`, `epoll.c`, `netlink`… | `kernel/*.c` |
| کامپوزیتور | `ishwl`: یک کامپوزیتور Wayland کوچک داخل مهمان؛ پیکسل هر پنجره از طریق فایل‌های mmap به اپ می‌رسد | `wl-bridge/` |
| دسکتاپ | DesktopKit: پنجره‌ها، tiling، workspace، تم‌ها، استور — SwiftUI | `desktop/DesktopKit/` |
| GPU | virtio-gpu در شبیه‌ساز → virglrenderer (Venus) → MoltenVK → Metal | `gpu/` |

مسیر یک پنجره لینوکسی تا iPad: `.desktop` → `ishwl-launch` → `fork/exec` در مهمان → بافر `wl_shm` → پل `LinuxGUIBridge` → یک `UIWindow` در DesktopKit. این زنجیره در `desktop/DesktopKit/Sources/DesktopKit/Linux/LinuxGUIBridge.swift` و `wl-bridge/src/main.c` قابل ردیابی است.

### ۱.۲ اعدادی که واقعاً وجود دارند

| چیز | مقدار | منبع |
|---|---|---|
| حجم سورس این مخزن | ۳۴ مگابایت، ۲٫۴۴۸ فایل | اندازه‌گیری روی همین کپی |
| System image پیش‌فرض | ۵۸۹ مبی‌بایت فشرده، ۲٫۲۴ گیگابایت بازشده، ۲۱۶٬۹۵۲ فایل | `release/CHECKLIST.md` |
| فایل نصب IPA نسخه ۱٫۵٫۰ | ۶۳۷ مگابایت | `release/source.json` |
| اپ‌های استور | ۸۰۰ (۷۸۰ apk + ۲۰ پک) | `Resources/Store/store-index.json` |
| اپ‌های «Works well» | ۲۳ (۶ مورد Experimental، ۷۷۱ مورد «Not tested») | `curation.json` |
| سرعت JIT نسبت به موتور gadget | حدود ۴٫۸ برابر (Node حدود ۱۲ برابر) | README + `jit/DESIGN.md` |
| پکیج‌های پایه مهمان | Alpine 3.21 + Firefox ESR + Thunar + foot + Node 22 + git | `release/build-rootfs.sh` |

این‌ها اعداد یک پروژه‌ی «کاغذی» نیست. برای نمونه، `kernel/oom.c` یک OOM-killer واقعی با PSI شبیه‌سازی‌شده و `oom_score` پیاده کرده، و `release/build-rootfs.sh` پنج مرحله build دارد که واقعاً اجرا شده‌اند (لاگ اندازه‌ها در `SIZES-*.txt` تولید می‌شود).

### ۱.۳ سه ادعایی که باید با احتیاط خوانده شوند

**الف) «همه‌چیز روی iPad اجرا می‌شود»** — نه. ماتریس سازگاری CLI در `benchmark/BENCHMARK_COMPAT.md` می‌گوید ۲۲۳ از ۲۲۳ تست پاس شده‌اند، اما همه‌شان ابزار خط فرمان‌اند (bash، gcc، python، node، apk). هیچ اپ GUI، هیچ اپ glibc/Electron و هیچ مرورگری در آن ماتریس نیست. ادعای «سازگاری کامل» از آن سند درنمی‌آید.

**ب) «JIT به‌طور خودکار روشن است»** — فقط اگر StikDebug نصب و pair شده باشد. بدون آن، اپ در «Compatibility mode» با موتور gadget اجرا می‌شود و همه‌چیز ۴ تا ۵ برابر کندتر است. برای iPadOS 26/27 مسیر TXM پیچیده‌تر هم هست (بخش ۶).

**ج) «Firefox، VS Code، VLC، Thunar پنجره‌های native هستند»** — درست است، اما با قیمت: VS Code و Wine از یک «جزیره glibc» با کتابخانه‌های Debian استفاده می‌کنند (`devtools/install-vscode.sh:45-56`)، و VLC از یک پلاگین Wayland از پیش ساخته‌شده (`release/CHECKLIST.md`). یعنی «native» یعنی پنجره native، نه باینری native.

### ۱.۴ مشکل پنهان: مهمان منقضی شده است

`release/build-rootfs.sh:107-110` مخازن را روی `v3.21/main` و `v3.21/community` قفل می‌کند و minirootfs هم `3.21.0` است. بر اساس تقویم رسمی Alpine، **شاخه 3.21 در ۱ نوامبر ۲۰۲۶ به EOL رسید**؛ شاخه پایدار فعلی 3.24.4 است. پیامدهای عملی:

- `apk upgrade` دیگر وصله امنیتی نمی‌آورد (فقط چیزی که در آینه 3.21 مانده).
- نسخه‌های Qt 6.11 / GTK / GNOME 50 / LLVM 22 که در 3.24 هستند در دسترس نیستند؛ بخشی از ناسازگاری اپ‌های Qt6 دقیقاً از همین نسخه‌های قدیمی می‌آید (`release/CHECKLIST.md` درباره Falkon).
- Mesa از edge می‌آید و با `linpad-pin-edge` قفل شده؛ این قفل روی 3.21 شکننده‌تر می‌شود.

این تنها موردی است که بدون build دوباره system image حل نمی‌شود — و در بخش ۳٫۳ آمده است.

---

## ۲. سخت‌افزار M5 در برابر محدودیت‌های iPadOS

### ۲.۱ مشخصات دقیق مدل شما

| مشخصه | iPad Pro M5 ۲۵۶/۵۱۲ گیگ | معنایش برای LinPad |
|---|---|---|
| رم | ۱۲ گیگابایت یکپارچه | سقف واقعی را iPadOS تعیین می‌کند، نه این عدد |
| CPU | ۹ هسته: ۳ عملکردی + ۶ کم‌مصرف | ترجمه JIT تک‌رشته‌ای است؛ هسته‌های P مهم‌ترند |
| GPU | ۱۰ هسته با Neural Accelerator | مسیر Venus/zink حداکثر از آن بهره می‌برد |
| پهنای باند حافظه | ۱۵۳ گیگابایت بر ثانیه | برای کپی بافرهای Wayland و حافظه مهمان کافی است |
| نمایشگر | ۱۱ اینچ ۲۴۲۰×۱۶۶۸ یا ۱۳ اینچ ۲۷۵۲×۲۰۶۴ | در مقیاس ۲، بار رندر نرم‌افزاری بالاست |

نکته مهم: نسخه ۱ ترابایتی و ۲ ترابایتی همان M5 با **۱۶ گیگابایت رم و ۱۰ هسته CPU** است. اگر روزی حافظه کم آوردید، تفاوت نسخه سخت‌افزاری است، نه تنظیمات.

### ۲.۲ گلوگاه واقعی: jetsam، نه رم

اپ iOS یک سقف حافظه «برای هر پروسه» دارد و وقتی به آن برسد، کل اپ کشته می‌شود — حتی اگر دستگاه ۱۲ گیگابایت رم داشته باشد. خود پروژه هم این را می‌داند:

- `release/INSTALL-DEVICE.md:120-124` می‌گوید build فعلی entitlement مربوط به افزایش سقف را **ندارد** و jetsam ممکن است اپ را حدود ۳ گیگابایت روی یک آیپد ۸ گیگی بکشد.
- `CHECKLIST.md` می‌گوید افزودن `com.apple.developer.kernel.increased-memory-limit` «اول باید توافق‌نامه برنامه توسعه‌دهنده را در developer.apple.com بپذیرید، بعد کلید را به `app/iSH.entitlements` اضافه کنید».

اندازه‌گیری‌های مستقل (غیررسمی) روی یک آیفون ۱۲ گیگی: حدود ۳٫۳ گیگابایت بدون entitlement و ۶ تا ۸ گیگابایت با آن. اپل عدد رسمی منتشر نمی‌کند و برای iPad Pro M5 ۱۲ گیگی هیچ اندازه‌گیری معتبری وجود ندارد. بنابراین عدد دقیق را باید خودتان با «Settings › Desktop › Performance overlay» و گزارش‌های `jetsam` روی دستگاه اندازه بگیرید.

این تنها تغییری است که سقف را جابه‌جا می‌کند؛ بقیه تنظیمات فقط داخل همان سقف جا باز می‌کنند.

### ۲.۳ چرا اضافه‌کردن entitlement برای شما راحت‌تر از بقیه است

AltStore Classic از نسخه ۲٫۲ (آوریل ۲۰۲۵) اپ‌هایی را که این entitlement را دارند، **حتی با Apple ID رایگان** نصب می‌کند. یعنی برای ساختن بیلد شخصی، لازم نیست حتماً حساب توسعه‌دهنده ۹۹ دلاری داشته باشید — اما اگر Xcode با تیم رایگان هنگام امضا خطا داد، تنها کاری که باید بکنید حذف همان پنج خط از `app/iSH.entitlements` است (بخش ۳٫۲).

### ۲.۴ JIT: تنها چیزی که ۴ تا ۵ برابر سرعت می‌دهد

بدون JIT، هر دستور مهمان با موتور gadget (ترجمه‌شده به بلوک‌های C) اجرا می‌شود. با JIT، کد ARM64 مهمان به کد ARM64 میزبان ترجمه و در یک ناحیه اجرایی ۱۲۸ تا ۵۱۲ مگابایتی کش می‌شود.

- مقدار پیش‌فرض کش در `jit/codemem.c:221` بر اساس حافظه آزاد انتخاب می‌شود: بیشتر از ۳ گیگابایت → ۲۵۶ مگابایت.
- در `jit/codemem.c:216-219` صریحاً نوشته شده که Firefox حدود ۳۵۰ مگابایت ترجمه در همه پروسه‌هایش نیاز دارد؛ در ۱۲۸ مگابایت «همیشه دوباره ترجمه می‌کند» و در ۲۵۶ «تقریباً جا می‌شود».
- اپ می‌تواند با `ISH_JIT_CACHE_MB` این را از Settings › Fast Mode › Code cache تنظیم کند، و `AppDelegate.m:242-246` تا ۱۰۲۴ مگابایت را قبول می‌کند — اما لیست UI در `FastMode.swift:64` فقط تا ۵۱۲ می‌رفت. **این را در پچ ما به ۷۶۸ و ۱۰۲۴ گسترش دادیم.**

برای M5 با ۱۲ گیگابایت، ۵۱۲ مگابایت انتخاب درست است؛ ۷۶۸ فقط اگر هم‌زمان سه چهار اپ سنگین باز می‌کنید معنا دارد (و هر مگابایت کش، یک مگابایت از سقف jetsam را می‌خورد).

---

## ۳. شخصی‌سازی و بهینه‌سازی برای M5 / ۱۲ گیگابایت

سه لایه وجود دارد. لایه A امروز و بدون هیچ ابزار اضافه‌ای روی دستگاه شما اجرا می‌شود؛ لایه B یک build دوباره اپ روی مک می‌خواهد؛ لایه C یک build دوباره system image.

| لایه | چه چیزی | ابزار لازم | سود تقریبی |
|---|---|---|---|
| A | تنظیمات اپ + اسکریپت مهمان | فقط ترمینال LinPad | متوسط تا زیاد (کش JIT، کش Firefox، malloc) |
| B | پچ روی سورس اپ | مک + Xcode | زیاد (سقف حافظه، swapfile، کش ۱ گیگ) |
| C | بازسازی system image روی Alpine 3.24 | مک + شبکه + حدود ۱ ساعت | زیاد (بسته‌های جدیدتر، امنیت) |

### ۳.۱ لایه A — بدون build، همین امروز

#### الف) تنظیمات خود اپ (Settings)

| تنظیم | مسیر | مقدار برای M5/۱۲GB | چرا |
|---|---|---|---|
| Code cache | Settings › Fast Mode › Code cache | **۵۱۲ MB** | Firefox حدود ۳۵۰ مگابایت ترجمه می‌خواهد؛ ۲۵۶ باعث ترجمه مکرر می‌شود |
| Fast mode | Settings › Fast Mode | **Automatic (StikDebug)** | بدون آن ۴ تا ۵ برابر کندتر |
| Close apps when memory runs out | Settings › Memory | **روشن** | با ۱۲ گیگابایت هم یک محافظ لازم است؛ خاموش‌کردن یعنی iPadOS کل اپ را می‌کشد |
| Never close | Settings › Memory | `code, firefox-esr, ishwl, foot` | جلوگیری از بسته‌شدن ادیتور یا مرورگر هنگام فشاری که خودشان ایجاد کرده‌اند |
| Performance overlay | Settings › Desktop | برای اولین روزها روشن | تنها راه دیدن `phys_footprint` واقعی روی این دستگاه |

نکته: مقدار «Code cache» فقط در **اجرای بعدی** اثر می‌گذارد، چون `AppDelegate.m:242-246` آن را قبل از شروع JIT به محیط می‌دهد.

#### ب) اسکریپت `m5-tune.sh`

فایل تحویلی: `personalize/m5-tune.sh`. داخل ترمینال LinPad (که با کاربر root باز می‌شود):

```sh
# فایل را داخل مهمان کپی کنید (از Files، یا با curl اگر جایی منتشرش کردید)
sh /root/m5-tune.sh --status   # ببینید الان چه چیزی اعمال است
sh /root/m5-tune.sh            # اعمال پروفایل
# بعد از اعمال: Settings › Lock Screen › Restart Desktop Session
sh /root/m5-tune.sh --undo     # برگشت به تنظیمات اصلی LinPad
```

این اسکریپت **دو فایل** می‌نویسد و یک بلوک به فایل سوم اضافه می‌کند؛ از هر فایل قبلی نسخه پشتیبان می‌گیرد:

| فایل | چه می‌کند | مقدار پیش‌فرض LinPad |
|---|---|---|
| `/etc/ishwl/session.d/25-m5.sh` | `MALLOC_ARENA_MAX=6` برای اپ‌های glibc (VS Code، Wine) | ۲ (فایل `15-lowmem.sh`) |
| `/etc/profile.d/99-linpad-m5.sh` | `NODE_OPTIONS=--max-old-space-size=4096` | تنظیم نشده |
| `/usr/lib/firefox-esr/browser/defaults/preferences/ish-tune.js` | یک بلوک مشخص در انتهای فایل: کش و پروسه بیشتر برای Firefox | یک پروسه، کش کوچک (`gecko-tune.sh`) |

مقادیر Firefox که عوض می‌شوند (با دلیل):

| کلید | LinPad | پروفایل M5 | دلیل |
|---|---|---|---|
| `dom.ipc.processCount` | ۱ | ۲ | با ۱۲ گیگابایت و کش ۵۱۲ مجاز است؛ بیشتر از ۲ فقط با کش ۱ گیگابایت |
| `browser.cache.memory.capacity` (KB) | ۱۶۳۸۴ | ۶۵۵۳۶ | رم بیشتر، کش بیشتر |
| `image.mem.surfacecache.max_size_kb` | ۱۳۱۰۷۲ | ۲۶۲۱۴۴ | تصاویر بزرگ‌تر بدون decode مکرر |
| `media.memory_caches_combined_limit_kb` | ۶۵۵۳۶ | ۱۳۱۰۷۲ | پخش ویدیو روان‌تر |
| `browser.sessionhistory.max_total_viewers` | ۰ | ۴ | Back/Forward بدون رندر دوباره |
| `layout.css.stylo-threads` | ۲ | ۴ | ۳ هسته عملکردی + ۶ کم‌مصرف |
| `javascript.options.mem.gc_max_helper_threads` | ۲ | ۳ | GC موازی‌تر |
| `browser.tabs.min_inactive_duration_before_unload` (ms) | ۶۰۰۰۰ | ۳۰۰۰۰۰ | تب‌های پس‌زمینه دیرتر آزاد می‌شوند |

نکته مهم درباره‌ی «مقدار بیشتر همیشه بهتر است»: این‌جا نه. هر پروسه اضافه Firefox یک ترجمه کامل دیگر از `libxul` می‌خواهد؛ روی شبیه‌ساز، رم زیاد به‌درد نمی‌خورد اگر کش کد تمام شود. به همین دلیل پیش‌فرض را روی ۲ گذاشتیم و بالا بردنش را مشروط به کش ۱ گیگابایت کردیم.

#### ج) تنظیمات مهمان که فقط با دستور ممکن است

```sh
# 1. وضعیت واقعی حافظه و GPU
cat /proc/ish/memory
vulkaninfo --summary | grep deviceName

# 2. اپ‌های سنگین را از کشتن معاف کنید (تا ری‌استارت بعدی)
printf 'protect code,firefox-esr\n' > /proc/ish/oom

# 3. به‌روزرسانی بسته‌های موجود (روی 3.21، فقط چیزی که در آینه مانده)
apk update && apk upgrade
```

### ۳.۲ لایه B — پچ روی اپ (ساخته و اعمال شد)

فایل: `personalize/app-m5.patch` — **روی همین کپی اعمال شده است**. سه تغییر:

| تغییر | فایل | خط | اثر |
|---|---|---|---|
| سقف حافظه iPadOS | `app/iSH.entitlements` | +۵ خط | اضافه‌شدن `com.apple.developer.kernel.increased-memory-limit` |
| کش کد ۷۶۸/۱۰۲۴ | `FastMode.swift:64` | ۱ خط | گزینه‌های بزرگ‌تر در UI |
| swapfile فشاری | `app/AppDelegate.m` | +۱۷ خط | فعال‌کردن `ISH_SWAPFILE=pressure` روی دستگاه‌های ≥ ۶ گیگابایت |

**درباره swapfile.** جالب‌ترین چیزی که در سورس پیدا شد: `kernel/swapfile.c` کامل پیاده شده اما **هیچ‌جا از سمت اپ روشن نمی‌شود**. سازوکارش این است که حافظه ناشناس مهمان را در یک فایل sparse حذف‌شده در `TMPDIR` اپ map می‌کند؛ چون این صفحات «external» هستند، در `phys_footprint` (عددی که jetsam با آن مقایسه می‌کند) حساب نمی‌شوند و iPadOS می‌تواند آن‌ها را روی SSD بنویسد و آزاد کند. حالت `pressure` فقط وقتی فعال می‌شود که به حد فشار نزدیک شده باشیم.

این یعنی با ۱۲ گیگابایت رم، مهمان می‌تواند عملاً از سقف jetsam هم عبور کند — به قیمت نوشتن روی SSD و کندی موقت. **این مسیر در نسخه منتشرشده تست نشده و کامنت خود سورس آن را «prototype for measuring» می‌نامد.** پس:

- قبل از استفاده، از مهمان backup بگیرید (Settings › Maintenance › Backup).
- اگر ناپایداری دیدید، با `LINPAD_NO_SWAPFILE=1` (یا حذف فراخوانی) خاموشش کنید.
- نوشتن روی SSD یعنی مصرف عمر درایو و مصرف باتری بیشتر؛ برای کارهای سبک لازم نیست.

**اعمال و برگرداندن پچ:**

```sh
# روی مک، داخل کلون پروژه
git apply --check personalize/app-m5.patch    # تست
git apply personalize/app-m5.patch            # اعمال
git apply -R personalize/app-m5.patch         # برگرداندن همه تغییرات
```

اگر Xcode هنگام امضا خطای entitlement داد (تیم رایگان)، فقط این پنج خط را از `app/iSH.entitlements` بردارید:

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

**ساخت روی مک (خلاصه؛ جزئیات در `release/INSTALL-DEVICE.md`):**

```sh
export PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH
gpu/build-third-party.sh          # یک‌بار
release/build-rootfs.sh           # حدود ۵۰ دقیقه
xcodebuild -skipMacroValidation -project iSH.xcodeproj -scheme iSH-ARM64 \
  -configuration Release -destination generic/platform=iOS \
  -allowProvisioningUpdates SYMROOT=$PWD/build-ios-release \
  IPHONEOS_DEPLOYMENT_TARGET=16.0 DEVELOPMENT_TEAM=<TEAM> ISH_JIT_BUILD=enabled build
release/embed-rootfs.sh --device "build-ios-release/Release-iphoneos/iSH ARM64.app" \
  release/out/ish-linux-rootfs-arm64.tar.gz
```

### ۳.۳ لایه C — بازسازی system image روی Alpine 3.24

این تنها کاری است که به macOS نیاز دارد و در همین گزارش نمی‌توانم انجامش دهم، ولی تغییراتش کوچک و مشخص است:

| فایل | خط | تغییر |
|---|---|---|
| `release/build-rootfs.sh` | ۵۳ | `MINIROOTFS=alpine-minirootfs-3.24.4-aarch64.tar.gz` |
| `release/build-rootfs.sh` | ۱۰۸-۱۰۹ | `v3.24/main` و `v3.24/community` |
| `release/guest/linpad-pin-edge` | — | بدون تغییر (خودش نسخه‌های جدیدتر از مخازن را قفل می‌کند) |
| `gpu/rootfs-add-gpu.sh` | ۱۵ | بازبینی Mesa: `edge` همچنان لازم است، ولی نسخه قفل‌شده `26.2.4-r0` را باید با نسخه موجود هم‌خوان کرد |
| `release/guest/linpad/store/linpad-store-index.mjs` | ۲۴ | `BRANCH='v3.21'` → `'v3.24'` |

سود: Qt 6.11 و GTK/GNOME جدیدتر، LLVM 22، ابزارهای ساختی که روی 3.21 نیستند، و — مهم‌تر از همه — وصله‌های امنیتی. ریسک: Mesa و `linpad-pin-edge` باید دوباره کالیبره شوند، و بعضی پک‌ها (Falkon، LibreOffice) ممکن است رفتار متفاوتی بدهند. قبل از انتشار، `release/check-public-rootfs.sh` و `release/CHECKLIST.md` را اجرا کنید.

اگر عجله ندارید: 3.23 (EOL نوامبر ۲۰۲۷) محافظه‌کارانه‌تر از 3.24 است و تغییرات کمتری در Mesa/Qt دارد.

### ۳.۴ نکات جانبی برای fork شخصی

چند چیز کوچک که در یک fork شخصی ارزش اصلاح دارند:

- دارایی `app/Assets.xcassets/Saddam Hussein.imageset/` (فایل `satanusen.png`) هیچ‌جا استفاده نمی‌شود — یک باقیمانده از دوره iSH است. حذفش حجم بیلد را کم می‌کند و بازبینی کد را تمیزتر.
- `MARKETING_VERSION` در `app/Project.xcconfig` روی `1.3.3` است در حالی که آخرین نسخه منتشرشده ۱٫۵٫۰ و `docs/idle-power.md` از «1.5.0 (4428)» حرف می‌زند. برای fork خودتان یک شناسه معنادار بگذارید (مثلاً `1.5.0-m5`)، وگرنه اپ متوجه نمی‌شود نسخه جدیدتر است.
- `release/source.json` را برای fork خودتان به مخزن خودتان اشاره بدهید تا SideStore به‌روزرسانی‌های شما را ببیند.

---

## ۴. «نصب هر نرم‌افزار لینوکسی» — واقعیت چیست

### ۴.۱ ماتریس فرمت‌ها

پرسش شما دقیقاً همین است: نرم‌افزاری که «در سطح همه نرم‌افزارها منتشر شده» راحت نصب شود. جدول زیر بر اساس سورس و مستندات پروژه است، نه حدس:

| فرمت / منبع | امروز در LinPad | چرا | راه‌حل |
|---|---|---|---|
| بسته Alpine (apk) | **کار می‌کند** | مخازن main+community روی 3.21 | استور ۷۸۰ اپ دارد؛ از ترمینال هر بسته‌ای نصب می‌شود |
| `.deb` (aarch64، glibc) | **امکان‌پذیر، مسیر ندارد** | musl در برابر glibc | `linpad-get` (ساخته شد) |
| AppImage | **امکان‌پذیر، مسیر ندارد** | FUSE نیست | `linpad-get` با `--appimage-extract` |
| tarball `.tar.gz/.xz/zst` | **امکان‌پذیر، مسیر ندارد** | فقط پک‌های دستی مثل VS Code | `linpad-get` |
| `.rpm` | امکان‌پذیر (libarchive) | فقط بسته‌های aarch64 معنا دارد | `linpad-get` |
| Flatpak | **غیرممکن** | به user namespace و bubblewrap نیاز دارد؛ `clone(CLONE_NEWUSER)` در `kernel/fork.c` با `EINVAL` رد می‌شود | هیچ |
| Snap | **غیرممکن** | به systemd نیاز دارد؛ مهمان OpenRC/بدون init است | هیچ |
| Docker | **غیرممکن** | namespace، cgroup، overlayfs | هیچ |
| نرم‌افزار x86_64 لینوکسی | **غیرممکن به‌طور مستقیم** | `kernel/elf.h:24` فقط `EM_AARCH64` را قبول می‌کند | Box64 (آزمایشی، از طریق Wine pack) |
| اپ Electron/Chromium glibc | **سخت اما ممکن** | glibc + نیاز به `--no-sandbox` | `linpad-get` + جزیره glibc |
| اپ WebKitGTK | **غیرممکن** | لایه سوکت شبیه‌ساز پشتیبانی نمی‌کند (`CHECKLIST.md:113`) | هیچ |
| وابسته به systemd (udev، journald…) | **غیرممکن** | init متفاوت است | هیچ |
| درایور کرنل / سخت‌افزار | **غیرممکن** | شبیه‌ساز کرنل واقعی نیست | هیچ |

### ۴.۲ چهار دیوار

**دیوار ۱ — معماری.** مهمان aarch64 است و هسته فقط ELF آرم ۶۴ بیتی را اجرا می‌کند (`kernel/elf.h:24`). هر باینری x86_64 — که اکثر بسته‌های «منتشرشده برای لینوکس» هستند — بدون لایه ترجمه باینری اجرا نمی‌شود. Box64 (که در پک `wine-x86` استفاده شده) می‌تواند بخشی از این کار را بکند، اما روی شبیه‌ساز یعنی ترجمه روی ترجمه و سرعت غیرقابل استفاده برای کار جدی.

**دیوار ۲ — libc.** اکوسیستم لینوکس دو نیمه است: glibc (Debian/Ubuntu/Fedora و تقریباً همه باینری‌های منتشرشده) و musl (Alpine). LinPad سمت musl است. پروژه برای VS Code و Wine یک «جزیره» ساخته: کتابخانه‌های Debian در `/usr/lib/aarch64-linux-gnu` و لودر در `/lib/ld-linux-aarch64.so.1`. این ایده کاملاً عمومی است و در `linpad-get` به یک سرویس نصب تبدیل شده. `gcompat` هم در Alpine هست، اما ناقص است و برای اپ‌های GUI جدی کافی نیست.

**دیوار ۳ — namespace و FUSE.** `CLONE_NEWUSER` و بقیه پرچم‌های namespace در `kernel/fork.c` با `EINVAL` برگردانده می‌شوند، `/dev/fuse` وجود ندارد. Flatpak، Snap، Docker و AppImage نوع ۲ همه به یکی از این دو نیاز دارند. این دیوار با کد مهمان یا اپ برداشته نمی‌شود؛ کار کرنل می‌خواهد.

**دیوار ۴ — systemd.** Snap و بخشی از نرم‌افزارهای دسکتاپ مدرن فرض می‌کنند `systemd` هست. مهمان LinPad init واقعی ندارد؛ `dbus` و `ishwl-session` نقشش را بازی می‌کنند، ولی `systemctl` نه.

### ۴.۳ وضعیت واقعی استور

استور در `desktop/DesktopKit/Sources/DesktopKit/Apps/Store/` یک ایندکس JSON می‌خواند که از APKINDEX های Alpine ساخته می‌شود:

- فقط **اپ‌های دسکتاپ** ایندکس می‌شوند: بسته‌هایی که AppStream دارند یا فایل `.desktop` دارند (`linpad-store-index.mjs:307-314`). ابزار خط فرمان دیده نمی‌شود مگر پک باشد.
- ایندکس روی `BRANCH='v3.21'` و `REPOS=['main','community']` سخت‌کد شده است (`:24-30`).
- برچسب سازگاری فقط از `curation.json` می‌آید؛ ۷۷۱ اپ از ۸۰۰ «Not tested» هستند (`StoreIndex.swift:134-137`).
- **هر اپی که در ایندکس نباشد، در استور نصب نمی‌شود** (`StoreModel.swift:210`). راه فرار: اپ «Packages» که `apk search` و `apk add` آزاد دارد، یا `linpad-get install apk:<name>`.
- بعد از نصب از اپ Packages، **لانچر به‌روز نمی‌شود** تا سشن ری‌استارت شود (`PackagesApp.swift:198` فقط `.guestFilesChanged` می‌فرستد). این یک باگ واقعی و آزاردهنده است.

### ۴.۴ چه چیزی امروز، بدون هیچ تغییری، کار می‌کند

اپ‌هایی که پروژه خودش «Works well» علامت زده: Firefox ESR، VS Code، Thunar/Files، VLC، GIMP (با قاعده X11)، Ristretto، Xarchiver، zathura، Claws Mail، Thunderbird، Transmission، FileZilla، Inkscape، SuperTux، Aisleriot، GNOME Mines، Zim، calcurse، tmux، Cheese، اسکنر OCR، Claude Code، GPU tools؛ LibreOffice (در استور «works» ولی در چک‌لیست انتشار تست نشده)، Audacity (آزمایشی)، Falkon/Dillo (آزمایشی)، Wine و Wine-x86 (آزمایشی).

`LinPad` با Node 22، npm، git، Python و ابزارهای build هم پایه است؛ یعنی هر چیزی که از `npm`/`pip` نصب شود مسیر عادی دارد.

---

## ۵. مسیر پیشنهادی: «نصب آسان» به‌جای «نصب دستی»

### ۵.۱ چیزی که ساخته شد: `linpad-get`

فایل: `personalize/linpad-get` — یک اسکریپت POSIX sh که داخل مهمان و با کاربر root اجرا می‌شود. **بدون build دوباره اپ** روی نسخه ۱٫۵٫۰ کار می‌کند، چون فقط از امکاناتی استفاده می‌کند که همین حالا در system image هست (`apk`, `node`, `debfetch.mjs`, جزیره glibc برای VS Code).

```sh
linpad-get install gimp                    # همان apk، مسیر مستقیم
linpad-get install ./app.deb               # بسته Debian (aarch64)
linpad-get install https://…/app.deb       # دانلود + نصب
linpad-get install ./App.AppImage          # بدون FUSE باز می‌شود
linpad-get install ./tool.tar.xz           # در /opt/linpad-get/<name>
linpad-get install ./pkg.rpm               # از طریق libarchive
linpad-get list                            # چه چیزی نصب شده
linpad-get remove <name>                   # برگشت
linpad-get island                          # ساخت/ترمیم جزیره glibc
linpad-get doctor                          # بررسی محیط
```

**چطور کار می‌کند، در چهار جمله:**

۱. فرمت را تشخیص می‌دهد (پسوند/اسکیم URL) و فایل را دانلود می‌کند.
۲. برای `.deb`/`.rpm`، پیلود را با `bsdtar` باز می‌کند و **هر فایل را جداگانه** کپی می‌کند — با دو محافظ: هر فایلی که مال یک بسته apk باشد (`apk info -W`) بازنویسی نمی‌شود، و هیچ بسته‌ای اجازه ندارد فایل‌های جزیره glibc یا لودر را جایگزین کند. این جلوی خراب‌شدن libc، داده‌های XKB و خود VS Code را می‌گیرد.
۳. اگر لودر Debian بتواند باینری را بارگذاری کند (یعنی glibc است، نه musl)، مطمئن می‌شود «جزیره glibc» هست و برایش یک لانچر در `/usr/local/bin` می‌سازد که `LD_PRELOAD` و `LD_LIBRARY_PATH` نشست را پاک می‌کند (وگرنه کتابخانه musl نشست داخل پروسه glibc بارگذاری می‌شود و کرش می‌کند — همان کاری که `devtools/vscode-launch` می‌کند).
۴. برای AppImage، به‌جای FUSE از `--appimage-extract` استفاده می‌کند، در `/opt/linpad-get/<name>` می‌گذارد، `.desktop` را با `Exec=` درست بازنویسی می‌کند و آیکون را کپی می‌کند.

**جزیره glibc** از `devtools/debfetch.mjs` استفاده می‌کند — همان ابزاری که VS Code و Wine را نصب می‌کند — با فهرستی از ۴۷ بسته کتابخانه‌ای Debian trixie؛ نام هر ۴۷ مورد با ایندکس رسمی `trixie/main/binary-arm64` تطبیق داده شد و همه موجودند.

**محدودیت‌های صادقانه‌ی این ابزار:**

- باینری‌های **x86_64** را نصب نمی‌کند؛ فقط aarch64.
- وابستگی‌های کتابخانه‌ای را خودکار از `Depends:` حل نمی‌کند؛ اگر کتابخانه‌ای کم باشد با `ld-linux --list` می‌گوید کدام است، ولی افزودنش دستی است (بسته Debian مربوطه را باید به فهرست جزیره اضافه کرد). برای اپ‌های معمولی GTK/Qt این فهرست کافی است؛ برای اپ‌های عجیب نه.
- `.desktop`هایی که `Terminal=true` دارند توسط DesktopKit نادیده گرفته می‌شوند (`LinuxDesktopEntry.swift:60-63`)، پس اپ‌های خط فرمان باید از ترمینال اجرا شوند.
- بعد از نصب، **لانچر را reload نمی‌کند** (همان باگ سمت اپ). یا با `Restart Desktop Session` یا با لاگ‌اوت/ورود، آیکون ظاهر می‌شود.

### ۵.۲ اولویت‌های بعدی برای «نصب آسان‌تر» (از دید کد)

بر اساس بررسی سورس، این هفت تغییر بیشترین اثر را دارند. تخمین‌ها برای کسی است که با Swift/SwiftUI آشناست و محیط build دارد.

| # | تغییر | نوع | تخمین | چرا مهم است |
|---|---|---|---|---|
| ۱ | جست‌وجوی آزاد در استور برای «نصب با نام بسته» + شیت تأیید و تخمین حجم | Swift | ۱ روز | امروز فقط شناسه‌های ایندکس نصب‌شدنی‌اند (`StoreModel.swift:210`) |
| ۲ | وقتی بسته‌ای در ایندکس نیست، `linpad-apps` خودش `toolkitOf`/`launchNeeds` را از ماژول ایندکس وارد کند و قاعده X11 و wrapper را بسازد | اسکریپت مهمان | ۲-۳ ساعت | بدون این، نصب دستی «نصب می‌شود ولی باز نمی‌شود» |
| ۳ | بعد از هر تغییر بسته، لانچر را reload کن (`PackagesApp` → `loadApplications`) | Swift | ۲ ساعت | باگ فعلی: اپ نصب‌شده تا ری‌استارت دیده نمی‌شود |
| ۴ | ساخت فهرست `.desktop` در زمان refresh داخل مهمان (به‌جای HTML زمان build) | اسکریپت مهمان | ۱ روز | پیش‌نیاز پشتیبانی از هر مخزن جدید |
| ۵ | جدول توصیف مخزن (branch/repo/AppStream) به‌جای `BRANCH` ثابت، و خطاناپذیرکردن AppStream | اسکریپت مهمان | ۱ روز | امکان ایندکس‌کردن edge/testing و مخزن شخص ثالث |
| ۶ | رابط «مخازن apk» در تنظیمات با حفظ قفل‌های نسخه (`linpad-pin-edge`) | Swift + اسکریپت | ۲ روز | امروز مخازن داخل image ثابت‌اند |
| ۷ | نوع نصب «بسته خارجی» در کاتالوگ: `.deb`/AppImage با اسکریپت، `.desktop` خودکار، ثبت وضعیت | Swift + اسکریپت | ۳-۴ روز | همان کاری که `linpad-get` دستی می‌کند، ولی از UI |

اگر هدف «کمترین کار برای بیشترین نتیجه» است، ترتیب ۳ ← ۲ ← ۱ را پیشنهاد می‌کنم.

### ۵.۳ گزینه‌های بلندپروازانه (با هزینه و ریسک)

| گزینه | چه می‌دهد | هزینه | نظر |
|---|---|---|---|
| Debian در chroot با proot | تقریباً هر بسته `.deb` بدون بازسازی | زیاد | proot از ptrace استفاده می‌کند؛ هر syscall تله می‌شود. روی شبیه‌ساز احتمالاً غیرقابل استفاده است. `proot` در Alpine community هست، پس تستش ارزان است |
| Box64 عمومی | باینری‌های x86_64 لینوکسی | متوسط | همین حالا در پک `wine-x86` استفاده می‌شود؛ برای اپ‌های GUI واقعی‌گرایانه نیست |
| Flatpak از طریق bwrap با setuid helper | نه | خیلی زیاد | بدون namespace کرنل، bwrap نمی‌تواند sandbox بسازد؛ setuid در iOS هم منتفی است |
| پورت FUSE در شبیه‌ساز | AppImage بدون extract، برخی اپ‌ها | خیلی زیاد | کار کرنل؛ خارج از محدوده |

---

## ۶. نصب روی iPad Pro M5 شما

### ۶.۱ سه مسیر نصب

| مسیر | چه می‌دهد | محدودیت |
|---|---|---|
| IPA آماده ۱٫۵٫۰ + SideStore/AltStore | سریع‌ترین راه | بدون پچ‌های M5؛ هر ۷ روز باید refresh شود |
| بیلد خودتان روی مک + `ideviceinstaller` | کنترل کامل (پچ‌ها، entitlement، rootfs جدید) | مک + Xcode + Apple ID |
| iloader/Sideloadly | فقط نصب IPA | همان محدودیت ۷ روز |

**محدودیت‌های حساب رایگان (۲۰۲۶):** هم‌زمان ۳ اپ نصب‌شده (شامل خود SideStore)، هر اپ بعد از ۷ روز منقضی، و ۱۰ App ID متفاوت در هفته. StikDebug و LocalDevVPN هم اپ سایدلودشده‌اند و همین سهمیه را می‌خورند. با حساب ۹۹ دلاری: بدون سقف ۳ اپ و گواهی ۳۶۵ روزه.

### ۶.۲ JIT روی iPadOS 27.2

ترتیب کارها:

۱. **Developer Mode** را در Settings › Privacy & Security روشن کنید.
۲. **StikDebug** را سایدلود کنید (نسخه‌ای که TXM را پشتیبانی می‌کند؛ برای iPadOS 26+ خودِ StikDebug می‌گوید «Supported — Limited App Availability»).
۳. **LocalDevVPN** را نصب و متصل کنید (StikDebug از طریق loopback به دستگاه وصل می‌شود).
۴. فایل pairing را از یک کامپیوتر بسازید (iloader این کار را می‌کند) و در StikDebug import کنید.
۵. LinPad را از Home Screen باز کنید؛ اسپلش باید «Enabling fast mode via StikDebug…» بگوید و بعد Quick Settings وضعیت **Native JIT ✓** را نشان دهد.

اگر شکست خورد: `Settings › Fast Mode › Status` دقیقاً می‌گوید کدام شرط برقرار نیست (StikDebug نصب نیست، get-task-allow نیست، یا بیلد بدون JIT است). «Retry fast mode» بعد از شروع لینوکس هم کار می‌کند، ولی فقط برای پروسه‌هایی که از آن لحظه به بعد اجرا می‌شوند.

### ۶.۳ چک‌لیست پس از نصب (روز اول)

```sh
# ۱. آیا JIT روشن است؟
fastfetch | head -20                  # باید Apple M5 و Venus را نشان دهد
cat /proc/ish/memory | head -5        # footprint و allowance

# ۲. حافظه واقعی چقدر است؟
awk '/MemTotal/ {print $2/1024 " MB"}' /proc/meminfo

# ۳. GPU
vulkaninfo --summary | grep deviceName

# ۴. به‌روزرسانی‌ها
apk update && apk upgrade
```

بعد در Settings:

- Code cache → ۵۱۲ مگابایت، سپس اپ را کامل ببندید و باز کنید.
- Performance overlay را روشن کنید و یک روز عادی کار کنید؛ عدد `phys_footprint` در اوج به شما می‌گوید چقدر به سقف jetsam نزدیک هستید. اگر در اوج از ۶۰٪ سقف رد شدید، entitlement را جدی بگیرید.

### ۶.۴ نکته مخصوص M5: نمایشگر و مقیاس

با نمایشگر ۲۷۵۲×۲۰۶۴ و مقیاس ۲، رندر نرم‌افزاری هر فریم گران است. اگر اپ‌های Wayland کند بودند، `/etc/ishwl/app-scale` را ببینید: خط `firefox-esr 2 1` یعنی در حالت عادی مقیاس ۲ و در fullscreen مقیاس ۱. برای کارهای گرافیکی، مقیاس ۱ در همه‌جا حدود یک‌سوم CPU هر فریم را کم می‌کند (به قیمت متن نرم‌تر).

---

## ۷. ریسک‌ها و محدودیت‌های سخت

| ریسک | شدت | توضیح | کاهش |
|---|---|---|---|
| Alpine 3.21 منقضی شده | بالا | از ۱ نوامبر ۲۰۲۶ وصله امنیتی ندارد | مهاجرت به 3.24 (بخش ۳٫۳) |
| همه‌چیز با root اجرا می‌شود | متوسط | ترمینال LinPad root است؛ `linpad-get` هم | فقط از منابع رسمی نصب کنید؛ backup |
| swapfile آزمایشی | متوسط | مسیر تست‌نشده در بیلد منتشرشده | backup، `LINPAD_NO_SWAPFILE=1` |
| بازنویسی فایل‌های سیستمی با `.deb` | متوسط | برخی بسته‌ها `/usr/lib` را عوض می‌کنند | محافظ `apk info -W` در `linpad-get` |
| انقضای گواهی ۷ روزه | بالا (عملیاتی) | اپ و StikDebug هر هفته | SideStore با refresh خودکار، یا حساب پولی |
| iPadOS سقف حافظه را کم کند | متوسط | گزارش‌هایی از کاهش سقف در iPadOS 26.4 روی آیپد ۸ گیگی | entitlement + اندازه‌گیری واقعی |
| GPLv3 | کم | اگر بیلد شخصی را پخش کنید، باید سورس بدهید | برای استفاده شخصی مسئله‌ای نیست |
| VS Code/Claude Code اختصاصی | کم | حق توزیع مجدد ندارند | خودتان از سایت رسمی نصب می‌کنید (همین کاری که پروژه می‌کند) |
| WebKitGTK | بالا برای برخی اپ‌ها | Geary، برخی مرورگرها | Claws Mail به‌جای Geary |

---

## ۸. برنامه اجرایی پیشنهادی

| گام | کار | زمان | چرا این ترتیب |
|---|---|---|---|
| ۰ | `Settings › Maintenance › Backup` — اولین کار، قبل از هر آزمایش | ۵ دقیقه | همیشه راه برگشت داشته باشید |
| ۱ | نصب ۱٫۵٫۰ با SideStore + StikDebug + LocalDevVPN | ۳۰-۶۰ دقیقه | بدون JIT بقیه کارها دردناک است |
| ۲ | Code cache = ۵۱۲، Memory protect list، Performance overlay | ۵ دقیقه | بیشترین سود با کمترین کار |
| ۳ | `m5-tune.sh` را اجرا و سشن را ری‌استارت کنید | ۱۰ دقیقه | کش Firefox و malloc |
| ۴ | یک روز کار عادی؛ عدد `phys_footprint` را یادداشت کنید | — | تصمیم می‌گیرید entitlement لازم است یا نه |
| ۵ | اگر مک دارید: پچ را روی کلون اعمال و بیلد کنید | ۲-۳ ساعت (+۵۰ دقیقه rootfs) | سقف حافظه + swapfile + کش ۱ گیگ |
| ۶ | `linpad-get` را نصب و با ۲-۳ اپ واقعی تست کنید (یک `.deb`، یک AppImage) | ۱ ساعت | مسیر نصب عمومی |
| ۷ | اگر جواب داد: مهاجرت rootfs به 3.24 | نصف روز | امنیت و بسته‌های جدید |

---

## ۹. پاسخ کوتاه به سؤال اصلی

> «می‌خواهم نرم‌افزارهای لینوکسی که همه‌جا منتشر شده‌اند، راحت روی این سیستم نصب شوند.»

**تا امروز:** فقط بسته‌های Alpine. استور ۸۰۰ اپ دارد ولی ۷۷۱ موردش تست نشده و هر چیزی که apk نباشد مسیر نصب ندارد.

**با کاری که در این گزارش انجام شد:** `.deb`، AppImage، tarball و rpm هم نصب می‌شوند — با یک دستور، روی نسخه‌ای که همین حالا نصب می‌کنید، بدون build. محدودیت باقی‌مانده دیگر «نصب» نیست؛ «اجرا»ست: نرم‌افزارهای x86_64، WebKitGTK و هر چیزی که به systemd یا namespace نیاز دارد، روی این معماری اجرا نمی‌شوند.

**آنچه هنوز واقعاً لازم است:** یک دکمه در استور به اسم «نصب با نام یا فایل» که همان `linpad-get` را صدا بزند، و یک refresh لانچر بعد از نصب. این دو، فاصله بین «ابزار خط فرمان برای حرفه‌ای‌ها» و «نصب آسان برای همه» را پر می‌کند.

---

## پیوست الف — فایل‌های تحویلی

| فایل | چیست |
|---|---|
| `docs/fa/linpad-m5-report.md` | همین گزارش |
| `personalize/m5-tune.sh` | پروفایل مهمان برای ۱۲ گیگابایت (اعمال/وضعیت/برگشت) |
| `personalize/linpad-get` | نصب‌کننده عمومی: apk، `.deb`، AppImage، tarball، rpm |
| `personalize/app-m5.patch` | پچ سمت اپ (اعمال‌شده در این کپی) |
| `personalize/README.md` | دستور نصب و استفاده، خلاصه |

## پیوست ب — منابع

**داخل مخزن:** `release/INSTALL-DEVICE.md`، `release/CHECKLIST.md`، `release/build-rootfs.sh`، `kernel/oom.c`، `kernel/swapfile.h`، `kernel/elf.h`، `kernel/fork.c`، `jit/codemem.c`، `devtools/install-vscode.sh`، `devtools/debfetch.mjs`، `release/guest/linpad/linpad-apps`، `release/guest/linpad/store/linpad-store-index.mjs`، `desktop/DesktopKit/Sources/DesktopKit/Apps/Store/*.swift`، `desktop/DesktopKit/Sources/DesktopKit/Core/System/FastMode.swift`.

**بیرون:** [Apple — iPad Pro specs](https://www.apple.com/ipad-pro/specs/) · [Apple — increased-memory-limit](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.kernel.increased-memory-limit) · [StikDebug](https://github.com/StikDebug/StikDebug) · [SideStore FAQ](https://docs.sidestore.io/docs/faq) · [AltStore PAL vs Classic](https://faq.altstore.io/altstore-pal-v.-altstore-classic) · [AltStore 2.2 و entitlement حافظه](https://www.idownloadblog.com/2025/04/16/altstore-v2-2-released/) · [Alpine releases](https://alpinelinux.org/releases/) · [Alpine downloads](https://alpinelinux.org/downloads/) · [TrollStore](https://github.com/opa334/TrollStore) · [AppImage docs](https://docs.appimage.org/user-guide/run-appimages.html).
