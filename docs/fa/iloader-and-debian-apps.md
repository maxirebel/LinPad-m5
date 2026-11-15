# نصب LinPad با iloader و نصب اپ‌های دبیان روی آن

> **دستگاه هدف:** iPad Pro M5، iPadOS 27.2
> **نسخه‌ای که نصب می‌شود:** LinPad 1.5.0 — `LinPad-1.5.0.ipa` (۶۳۷ مگابایت)
> **تاریخ:** ۱۴ نوامبر ۲۰۲۶
> **وضعیت:** فقط گزارش؛ هیچ تغییری روی دستگاه یا پروژه اعمال نشده است.
> **گزارش مرتبط:** [`linpad-m5-report.md`](linpad-m5-report.md) — شخصی‌سازی و بهینه‌سازی برای M5/۱۲GB.

---

## خلاصه

**الف) نصب با iloader** کار می‌کند و کوتاه‌ترین مسیر است، ولی یک ریسک مشخص دارد: مستندات رسمی iloader دستگاه‌ها را تا **iPadOS 26.2** پشتیبانی می‌کند و شما روی **27.2** هستید. گزارش‌های میدانی می‌گویند روی 27 هم نصب انجام می‌شود، ولی جایی که روی 27 می‌شکند، **ساخت pairing file** است — نه خود نصب. اگر در گام «شناسایی دستگاه»، «ورود Apple ID» یا ساخت pairing file گیر کردید، چند جایگزین دارید (بخش ۱٫۶).

**ب) نصب اپ‌های دبیان** روی LinPad به‌طور مستقیم ممکن نیست، چون LinPad یک Alpine/musl است و `dpkg/apt` ندارد. اما **بیشتر اپ‌های دبیان با `.deb` آرم‌۶۴ نصب‌شدنی‌اند**، به شرط اینکه با «جزیره glibc» و یک لانچر درست اجرا شوند — همان کاری که ابزار `personalize/linpad-get` انجام می‌دهد. سه دسته استثنا وجود دارد: اپ‌های x86_64-only، اپ‌های Qt که کتابخانه Qt دبیان می‌خواهند، و هر چیزی که به systemd/FUSE/namespace وابسته است.

**ج) خبر خوب:** بیشتر اپ‌هایی که مردم «اپ دبیان» صدا می‌زنند — GIMP، Inkscape، LibreOffice، KeePassXC، VLC، Thunderbird، Chromium، Firefox، Krita، Blender، Zotero، Okular، Telegram — بستهٔ Alpine دارند و **اصلاً `.deb` نمی‌خواهند**. اول این مسیر را چک کنید (بخش ۲٫۳).

---

## بخش ۱ — نصب IPA با iloader

### ۱.۱ پیش‌نیازها

| چیز | جزئیات |
|---|---|
| کامپیوتر | Windows 10/11، macOS 10.15+، یا Linux |
| درایور USB | Windows: **iTunes کلاسیک** (نسخه Microsoft Store گاهی usbmuxd را نصب نمی‌کند). macOS: همراه سیستم. Linux: `usbmuxd` |
| ابزار | iloader **v2.4.1** — فقط از [iloader.site/download](https://iloader.site/download/) یا [GitHub releases](https://github.com/nab138/iloader/releases). نسخه‌های بازبسته‌بندی‌شده در سایت‌های ثالث را نصب نکنید |
| کابل | USB داده‌دار (کابل‌های شارژ ارزان اغلب فقط برق دارند) |
| حساب | هر Apple ID با ورود دو مرحله‌ای؛ لازم نیست با حساب خود آیپد یکی باشد |
| آیپد | Developer Mode روشن (iOS 16+) + حداقل ~۴ گیگابایت فضای آزاد |
| فایل | `LinPad-1.5.0.ipa` — [لینک مستقیم](https://github.com/fspecii/LinPad/releases/download/v1.5.0/LinPad-1.5.0.ipa) (۶۳۷٬۰۰۶٬۰۲۶ بایت — بررسی شد و زنده است) |

### ۱.۲ هشدار سازگاری: iPadOS 27.2

سند سیستم‌موردنیاز رسمی iloader این بازه‌ها را می‌نامد: **15.0–15.8.5، 16.0–17.7.7، 18.0–26.2**. iPadOS 27.2 بیرون از این لیست است.

شواهد میدانی (انجمن‌ها و گزارش کاربران، سپتامبر–نوامبر ۲۰۲۶) می‌گویند:

- خودِ **نصب IPA روی 27 کار می‌کند** (StikDebug و SideStore هم روی 27.0 تست و تأیید شده‌اند).
- آنچه روی 27 می‌شکند، **انتقال pairing file** است؛ بعضی کاربران با iloader موفق نشده‌اند و با Impactor یا ابزارهای جدیدتر موفق شده‌اند. از iOS 26.4 به بعد، Apple مکانیزم pairing را عوض کرده و یک «remote pairing file» لازم است که باید روی کامپیوتر ساخته شود.
- یعنی: انتظار داشته باشید نصب انجام شود، ولی اگر بعداً خواستید JIT (بخش ۱٫۵) را روشن کنید، ممکن است گام pairing دردسر داشته باشد.

### ۱.۳ کدام IPA را نصب کنید

| مورد | مقدار |
|---|---|
| فایل | `LinPad-1.5.0.ipa` |
| Bundle ID | `com.valentinneagu.ish.arm64` |
| کمترین iPadOS | ۱۷٫۰ |
| حجم | ۶۳۷ مگابایت (شامل system image فشردهٔ ۵۸۹ مبی‌بایتی) |
| فضای لازم بعد از نصب | حدود ۳ گیگابایت (تصویر لینوکس ۲٫۲۴ گیگابایت باز می‌شود) |

**نکته مهم:** این IPA همان نسخهٔ رسمی پروژه است. یعنی **پچ‌های M5 این پروژه را ندارد**: نه entitlement افزایش حافظه، نه کش کد ۱۰۲۴، نه swapfile. اگر بعداً خواستید آن‌ها را داشته باشید، باید خودتان روی مک build کنید (بخش ۳٫۲ گزارش قبلی).

### ۱.۴ مراحل نصب

**گام ۰ — Developer Mode.** روی آیپد: `Settings › Privacy & Security › Developer Mode` را روشن کنید و دستگاه را ری‌استارت کنید. بعد از ری‌استارت، تأیید دوباره با رمز دستگاه لازم است.

**گام ۱ — iTunes (فقط Windows).** از سایت اپل نصب کنید و یک‌بار بازش کنید تا سرویس‌های usbmuxd نصب شوند. بعد می‌توانید ببندید. اگر iTunes از Microsoft Store نصب کرده‌اید و iloader دستگاه را نمی‌بیند، همان نسخه را حذف و نسخه کلاسیک را نصب کنید.

**گام ۲ — iloader.** از صفحه دانلود رسمی، نسخه ۲.۴.۱ را برای سیستم‌تان بگیرید و اجرا کنید.

**گام ۳ — اتصال.** کابل را وصل کنید، آیپد را باز کنید و روی «Trust This Computer» بزنید و رمز را وارد کنید.

**گام ۴ — دستگاه و حساب.** در iloader دستگاه باید در لیست بیاید. با Apple ID وارد شوید و کد دو مرحله‌ای را بدهید. اگر ورود شکست خورد، گزینهٔ **Anisette server** را عوض کنید (iloader چند سرور پیشنهاد می‌دهد) و اگر باز هم نشد، از مسیر `Reset Anisette State` استفاده کنید.

**گام ۵ — نصب IPA.** گزینهٔ **Install IPA / Sideload IPA** را بزنید و `LinPad-1.5.0.ipa` را انتخاب کنید. با ۶۳۷ مگابایت، روی USB 2 ممکن است ۵ تا ۱۵ دقیقه طول بکشد. در این مرحله iloader اپ را با گواهی حساب شما امضا می‌کند؛ **گواهی هفت‌روزه** است.

**گام ۶ — اعتماد به پروفایل.** اگر آیپد گفت «Untrusted Developer»: `Settings › General › VPN & Device Management › <your Apple ID> › Trust`.

**گام ۷ — اولین اجرا.** LinPad باز می‌شود، اسپلش می‌آید و شروع می‌کند به باز کردن تصویر لینوکس: «Unpacking Linux… N of 690 MB». روی M5 حدود ۵ تا ۱۰ دقیقه. اپ را نبندید و در این مدت به Wi-Fi وصل باشید. بعد از آن «Configuring…» و «Starting desktop…».

**گام ۸ — بررسی.** داخل ترمینال (foot):

```sh
fastfetch | head -20                  # باید Apple M5 و Venus را نشان دهد
cat /proc/ish/memory | head -5        # footprint و allowance واقعی
vulkaninfo --summary | grep deviceName
```

اگر «Compatibility mode» دیدید، یعنی JIT روشن نیست — بخش بعدی.

### ۱.۵ روشن‌کردن JIT (اختیاری ولی مهم)

JIT فقط وقتی فعال می‌شود که یک **دیباگر** به پروسه وصل شود. LinPad خودش دیباگر ندارد؛ از StikDebug می‌خواهد این کار را بکند.

1. **StikDebug** را هم با iloader نصب کنید (از همان صفحه، یا IPA رسمی StikDebug). این هم اپ سایدلودشده است و همان سهمیهٔ ۳ اپ و ۷ روز را می‌خورد.
2. **LocalDevVPN** را نصب و وصل کنید. StikDebug از طریق یک تونل loopback به خود دستگاه وصل می‌شود. (در بعضی منطقه‌ها این اپ در App Store نیست؛ در آن صورت نسخهٔ سایدلودشدهٔ آن را استفاده کنید.)
3. **Pairing file** بسازید. iloader می‌تواند pairing file بسازد و export کند (منوی pairing/documents). فایل را با AirDrop/Files به آیپد ببرید و در StikDebug import کنید. روی iPadOS 26.4+ این فایل باید از نوع remote pairing باشد.
4. LinPad را از **Home Screen** باز کنید (نه از داخل StikDebug). اسپلش باید «Enabling fast mode via StikDebug…» بگوید.
5. تأیید: Quick Settings باید **Native JIT ✓** نشان دهد، و `Settings › Fast Mode › Status` بگوید «On».

اگر شکست خورد: `Settings › Fast Mode` دلیل را می‌گوید (StikDebug نصب نیست / get-task-allow نیست / بیلد بدون JIT). دکمهٔ «Retry fast mode» بعد از شروع لینوکس هم کار می‌کند، ولی فقط برای برنامه‌هایی که از آن لحظه به بعد اجرا می‌شوند.

### ۱.۶ اگر iloader روی iPadOS 27 کار نکرد

| جایگزین | مزیت | عیب |
|---|---|---|
| **Impactor** | روی 27 با pairing درست گزارش موفقیت دارد | رابط ساده‌تر، مستندات کمتر |
| **Sideloadly** | بالغ‌ترین ابزار ویندوز | نیاز به iTunes، رابط قدیمی |
| **AltStore Classic 2.2+** | تنها گزینه‌ای که entitlement افزایش حافظه را با حساب رایگان می‌پذیرد | نیاز به AltServer روی PC و همان ۷ روز |
| **SideStore + iloader** | refresh خودکار در دستگاه | pairing روی 27 حساس است |
| **مک + Xcode** | تنها مسیر قطعی روی iPadOS 27؛ entitlement و JIT هم با آن ممکن است | مک لازم است |

### ۱.۷ انقضا، تمدید، و سهمیه

| موضوع | با Apple ID رایگان |
|---|---|
| عمر گواهی | حدود ۷ روز؛ بعد از آن اپ باز نمی‌شود |
| تعداد اپ نصب‌شده | ۳ اپ هم‌زمان (شامل SideStore/StikDebug) |
| App ID در هفته | ۱۰ مورد |
| هشدار ۲۰۲۶ | Apple بعضی تیم‌های رایگان را «soft-ban» کرده و نصب با `0xe8008024` («The provisioning profile is banned») رد می‌شود؛ در این حالت باید گواهی/pairing را نو کرد یا حساب دیگری امتحان کرد |

**تمدید:** دو راه — الف) همان IPA را دوباره با iloader نصب کنید؛ ب) SideStore را باز بگذارید تا خودش refresh کند. **دادهٔ لینوکس با نصب دوبارهٔ همان bundle id پاک نمی‌شود**؛ فقط اگر اپ را حذف (uninstall) کنید، تصویر لینوکس و فایل‌هایتان از بین می‌رود.

### ۱.۸ عیب‌یابی

| نشانه | علت محتمل | کار |
|---|---|---|
| دستگاه در iloader نیست | iTunes/usbmuxd، کابل، Trust | کابل داده‌دار، تعویض پورت، نصب مجدد iTunes کلاسیک |
| ورود Apple ID شکست می‌خورد | anisette server | عوض‌کردن سرور، `Reset Anisette State` |
| نصب با خطا تمام می‌شود | امضا/App ID | گواهی‌های قدیمی را revoke کنید، حساب دیگری |
| «Untrusted Developer» | پروفایل تأیید نشده | Settings › VPN & Device Management › Trust |
| اپ بلافاصله بسته می‌شود | گواهی منقضی/بن‌شده | نصب دوباره |
| «Unpacking» گیر می‌کند | فضای کم یا app background | ۴ گیگابایت آزاد کنید، اپ را جلو نگه دارید |
| JIT روشن نمی‌شود | StikDebug/LocalDevVPN/pairing | بخش ۱٫۵ |

---

## بخش ۲ — نصب اپ‌های لینوکسی دبیان

### ۲.۱ چرا `.deb` مثل دبیان نصب نمی‌شود

| تفاوت | دبیان | LinPad |
|---|---|---|
| مدیر بسته | `dpkg` + `apt` | `apk` (Alpine) |
| libc | glibc | musl |
| معماری رایج بسته‌های منتشرشده | `amd64` (x86_64) | `aarch64` |
| init/سرویس | systemd | بدون systemd (`dbus` + `ishwl-session`) |
| sandbox | FUSE، namespace، seccomp | هیچ‌کدام |

پس `.deb` را نمی‌شود «نصب» کرد؛ باید **باز کرد و کنار سیستم گذاشت** — دقیقاً همان کاری که پروژه برای VS Code و Wine می‌کند.

### ۲.۲ درخت تصمیم

```
اپ مورد نظر چیست؟
├── بستهٔ Alpine دارد؟  ── بله ──▶ apk add  (سطح ۱: بهترین، سریع‌ترین)
├── سازنده .deb arm64 می‌دهد؟ ── بله ──▶ linpad-get  (سطح ۲)
├── سازنده AppImage/tar برای arm64 می‌دهد؟ ── بله ──▶ linpad-get (سطح ۳)
├── فقط x86_64 است؟ ──▶ اجرا نمی‌شود (Box64 فقط برای برخی موارد)
└── به systemd/FUSE/namespace نیاز دارد؟ ──▶ اجرا نمی‌شود
```

### ۲.۳ سطح ۱ — اول دنبال معادل Alpine بگردید

اکثر «اپ‌های دبیان» که مردم می‌خواهند، بستهٔ Alpine دارند. این را جدی بگیرید: نصب apk ساده‌تر، سریع‌تر، به‌روزتر و پایدارتر است.

```sh
apk search -v keepassxc       # آیا هست؟
apk info keepassxc            # جزئیات
apk add keepassxc             # نصب
```

یا از اپ **Packages** در دسکتاپ (جست‌وجوی آزاد روی `apk search`)، یا [pkgs.alpinelinux.org](https://pkgs.alpinelinux.org/packages).

اپ‌هایی که **همین حالا** در Alpine 3.21 (همان چیزی که LinPad دارد) بسته دارند:

| اپ | بسته | اپ | بسته |
|---|---|---|---|
| GIMP | `gimp` | Inkscape | `inkscape` |
| LibreOffice | `libreoffice` | KeePassXC | `keepassxc` |
| VLC | `vlc` | Thunderbird | `thunderbird` |
| Firefox | `firefox-esr` / `firefox` | Chromium | `chromium` |
| Krita | `krita` | Blender | `blender` |
| Audacity | `audacity` | Zotero | `zotero` |
| Okular | `okular` | Evince | `evince` |
| Telegram Desktop | `telegram-desktop` | Wireshark | `wireshark` |
| Remmina | `remmina` | GParted | `gparted` |
| Syncthing | `syncthing` | Nextcloud | `nextcloud-client` |
| Geany | `geany` | Meld | `meld` |
| SQLite Browser | `sqlitebrowser` | Thonny | `thonny` |
| FileZilla | `filezilla` | Transmission | `transmission-gtk` |
| HexChat | `hexchat` | Pidgin | `pidgin` |
| Zathura | `zathura` | Thunar | `thunar` |

**این‌ها را با `.deb` نصب نکنید.** حتی اگر نسخهٔ دبیانشان جدیدتر باشد، نسخهٔ Alpine با musl و کتابخانه‌های سیستم هماهنگ است و دردسر ندارد.

اپ‌هایی که بستهٔ Alpine **ندارند** (بخش ۲٫۴ و ۲٫۵ به کار می‌آید): Obsidian، Signal، Discord، Slack، Zoom، Spotify، VSCodium، Element، OnlyOffice، Godot، Joplin، Logseq، Vivaldi، Brave.

### ۲.۴ سطح ۲ — نصب `.deb` با `linpad-get`

این ابزار در پوشهٔ `personalize/` همین پروژه است و کارش دقیقاً همین است.

#### الف) آماده‌سازی (یک‌بار)

```sh
# ابزار را داخل مهمان ببرید (curl یا Files)، بعد:
chmod 755 /usr/local/bin/linpad-get
linpad-get doctor          # چه چیزی هست، چه چیزی نیست
linpad-get island          # ساخت جزیره glibc: یک‌بار، چند صد مگابایت
```

اگر VS Code یا Wine را قبلاً نصب کرده‌اید، جزیره از قبل هست و این گام سریع تمام می‌شود.

#### ب) انتخاب فایل درست

در صفحهٔ دانلود سازنده، دنبال این‌ها بگردید:

- `..._arm64.deb` یا `..._aarch64.deb` ✅
- `..._all.deb` ✅ (فقط داده/اسکریپت است)
- `..._amd64.deb` یا `..._x86_64.deb` ❌ (روی LinPad اجرا نمی‌شود)
- `..._armhf.deb` ❌ (۳۲ بیتی)

اگر فقط AppImage یا tar.gz برای arm64 هست، بخش ۲٫۵.

#### ج) نصب

```sh
linpad-get install ./signal-desktop_7.x_arm64.deb
# یا از URL
linpad-get install https://<سایت سازنده>/<app>_<نسخه>_arm64.deb   # آدرس واقعی را از صفحهٔ دانلود بردارید
```

پشت صحنه چه می‌شود:

1. `data.tar.*` باز می‌شود و **هر فایل جداگانه** در ریشه کپی می‌شود — با محافظ: فایل‌های متعلق به apk و فایل‌های جزیرهٔ glibc بازنویسی نمی‌شوند.
2. برای هر برنامهٔ glibc در `/usr/bin` یک لانچر در `/usr/local/bin` ساخته می‌شود که `LD_PRELOAD` و `LD_LIBRARY_PATH` نشست را پاک می‌کند.
3. اگر `.desktop` همراه بسته نباشد، یکی ساخته می‌شود.
4. فهرست فایل‌ها ذخیره می‌شود تا `linpad-get remove <name>` دقیقاً همان‌ها را پاک کند.

بعد از نصب، یک‌بار **Restart Desktop Session** لازم است تا آیکون ظاهر شود.

#### د) اولین اجرا و عیب‌یابی

همیشه اول از ترمینال اجرا کنید تا خطا را ببینید:

```sh
signal-desktop            # نام لانچر
# یا مسیر واقعی:
/usr/bin/signal-desktop
```

| خطا | معنی | کار |
|---|---|---|
| `error while loading shared libraries: libfoo.so.1` | کتابخانه در جزیره نیست | بخش ۲٫۴٫هـ |
| `The SUID sandbox helper binary was found, but is not configured correctly` | اپ Electron است و sandbox می‌خواهد | با `--no-sandbox` اجرا کنید (پایین) |
| `Failed to create wl_display` / `cannot open display` | اپ X11 است | قاعدهٔ X11 (پایین) |
| `Settings schema '…' is not installed` | داده‌های اسکیمای GTK کامل نیست | `apk add glib-dev` سپس `glib-compile-schemas /usr/share/glib-2.0/schemas` |
| `Gtk-WARNING: cannot open display:` | محیط Wayland به اپ نرسیده | از لانچر دسکتاپ اجرا کنید، نه از SSH |

**اپ‌های Electron** (Signal، Slack، Discord، Element، VS Code): چون LinPad نه seccomp دارد نه user namespace، sandbox کروم کار نمی‌کند و باید خاموش شود:

```sh
# دستی
/usr/bin/signal-desktop --no-sandbox
# یا در لانچر: بعد از unset ها، exec را این‌طور کنید
# exec "/usr/bin/signal-desktop" --no-sandbox "$@"
```

و برای اینکه Wayland را انتخاب کند:

```sh
export ELECTRON_OZONE_PLATFORM_HINT=wayland
```

**اپ‌های X11** (بعضی قدیمی‌ها): باید یک قاعده در `/etc/ishwl/apps` داشته باشند تا ishwl برایشان Xwayland باز کند:

```sh
printf 'myapp x11\n' >> /etc/ishwl/apps
```

**اپ‌های Qt6** (KeePassXC دبیان، VLC دبیان، بعضی ابزارها): `.deb` خودش Qt را ندارد؛ باید کتابخانه‌های Qt6 دبیان هم به جزیره اضافه شوند. فهرست کوتاه (نام‌ها در trixie بررسی شده‌اند):

```
libqt6core6t64 libqt6gui6 libqt6widgets6 libqt6dbus6 libqt6network6 libqt6svg6 qt6-wayland
```

این‌ها را به `BASE_LIBS` در `linpad-get` اضافه کنید و `linpad-get island` را دوباره اجرا کنید. Qt6 کامل حدود ۱۵۰ مگابایت است؛ برای هر اپ Qt فقط یک‌بار.

#### هـ) وقتی کتابخانه کم است

```sh
# چه چیزی کم است؟
env -u LD_PRELOAD /lib/ld-linux-aarch64.so.1 --list /usr/bin/myapp | grep 'not found'
```

بعد:

1. در [packages.debian.org](https://packages.debian.org/search?searchon=contents) نام فایل کتابخانه را جست‌وجو کنید (گزینهٔ «Search the contents of packages»، معماری arm64، توزیع trixie).
2. نام بستهٔ دبیان را بگیرید.
3. آن را به `BASE_LIBS` در `linpad-get` اضافه کنید.
4. `linpad-get island` را دوباره اجرا کنید.

این کار «حل خودکار وابستگی» نیست، ولی برای اپ‌های معمولی GTK بعد از یکی دو بار تنظیم، تمام می‌شود.

#### و) حذف

```sh
linpad-get list
linpad-get remove signal-desktop
```

### ۲٫۵ سطح ۳ — AppImage و tarball

اگر سازنده فقط AppImage یا tar می‌دهد:

```sh
linpad-get install ./MyApp-1.2-arm64.AppImage
# یا
linpad-get install ./postman.tar.gz
```

AppImage به‌جای FUSE باز (extract) می‌شود و در `/opt/linpad-get/<name>` می‌نشیند؛ tarball هم همین‌طور. هر دو لانچر و آیکون می‌گیرند.

اگر AppImage خودش اجرا نشد:

```sh
./App.AppImage --appimage-extract
./squashfs-root/AppRun
```

### ۲٫۶ سطح ۴ — chroot دبیان: ممکن است، ولی توصیه نمی‌شود

ایدهٔ وسوسه‌انگیز: یک rootfs دبیان بسازیم، `chroot` کنیم و با `apt` هر بسته‌ای نصب کنیم. سه واقعیت دربارهٔ LinPad:

۱. **`chroot` کار می‌کند.** `sys_chroot` در `kernel/fs.c:884` پیاده شده و چون ترمینال LinPad با root اجرا می‌شود، محدودیتی ندارد.
۲. **`mount` هم تا حدی کار می‌کند.** `fs/mount.c:178` فقط چهار فایل‌سیستم را می‌شناسد: `realfs`، `procfs`، `devpts` و `tmpfs`. یعنی `mount -t proc proc /mnt/proc` و `mount -t devpts` جواب می‌دهند.
۳. **ولی `bind mount` پشتیبانی نمی‌شود.** پرچم `MS_BIND` در `MS_SUPPORTED` نیست (`fs/mount.c:175`) و با `EINVAL` برمی‌گردد. این همان چیزی است که chroot را برای کار GUI بی‌فایده می‌کند: نمی‌توانید `/dev`، `/sys` و — مهم‌تر از همه — پوشهٔ سوکت Wayland (`/tmp/xdg-runtime`) را داخل chroot شریک کنید. بدون آن، هیچ اپ گرافیکی داخل chroot به کامپوزیتور نمی‌رسد.

وضعیت `proot` هم بد نیست بدانید: در Alpine 3.21 (همان تصویر LinPad) بستهٔ `proot` **وجود ندارد** (در 3.24 اضافه شده)، ولی `debootstrap` و `dpkg` و `jchroot` در 3.21 هستند. پس یک chroot «دستی» ساختنی است — فقط برای کارهای خط فرمان.

**نتیجه:** برای اپ‌های GUI، مسیر استخراج `.deb` (سطح ۲) هم سریع‌تر است، هم سبک‌تر، هم با دسکتاپ یکپارچه. chroot را برای کارهای خاص (ساختن بسته، تست CLI) نگه دارید، نه برای نصب اپ روزمره.
### ۲٫۷ چه چیزی هیچ‌وقت کار نمی‌کند

| مورد | چرا |
|---|---|
| `flatpak install` | به user namespace و bubblewrap نیاز دارد؛ `CLONE_NEWUSER` در `kernel/fork.c` با `EINVAL` رد می‌شود |
| `snap install` | snapd به systemd نیاز دارد |
| Docker / Podman | namespace، cgroup، overlayfs |
| باینری x86_64 لینوکسی | `kernel/elf.h` فقط `EM_AARCH64` را می‌پذیرد |
| AppImage نوع ۲ بدون extract | FUSE نیست (ولی extract کار می‌کند) |
| اپ‌های WebKitGTK | لایهٔ سوکت شبیه‌ساز پشتیبانی نمی‌کند |
| درایور کرنل / USB / چاپگر | شبیه‌ساز کرنل واقعی نیست |
| سرویس‌های systemd | init وجود ندارد |

### ۲٫۸ جدول شانس موفقیت اپ‌های معروف

| اپ | بهترین مسیر | شانس | یادداشت |
|---|---|---|---|
| VS Code | پک `vscode` در استور | ✅ تأییدشده | خود پروژه نصبش می‌کند |
| Signal | `.deb` arm64 + `--no-sandbox` | 🟡 محتمل | Electron، سنگین؛ سازنده نسخهٔ arm64 می‌دهد |
| Slack | `.deb` arm64 + `--no-sandbox` | 🟡 محتمل | Electron، حافظه‌بر |
| Element | `.deb` arm64 + `--no-sandbox` | 🟡 محتمل | Electron |
| VSCodium | `.deb` arm64 یا AppImage | 🟡 محتمل | همان Chromium، بدون تلمتری |
| Discord | `.deb` — معمولاً فقط amd64 | ❌/🟡 | قبل از دانلود نام فایل را چک کنید |
| Obsidian | نسخهٔ arm64 رسمی معمولاً نیست | ❌ | فقط x86_64 منتشر می‌شود؛ buildهای اجتماعی arm64 وجود دارد |
| Spotify | `.deb` — معمولاً فقط amd64 | ❌ | Widevine هم مسئله است |
| KeePassXC | `apk add keepassxc` | ✅ | نسخهٔ Alpine موجود است |
| LibreOffice | `apk add libreoffice` یا پک استور | ✅/🟡 | پک استور آزمایشی است |
| GIMP | `apk add gimp` + قاعدهٔ X11 | ✅ تأییدشده | پروژه تست کرده |
| Telegram Desktop | `apk add telegram-desktop` | 🟡 | Qt6؛ در استور نیست، دستی نصب کنید |
| Zoom | — | ❌ | نسخهٔ لینوکسی arm64 عمومی ندارد |
| Docker | — | ❌ | namespace ندارد |
| Steam | — | ❌ | x86_64 + گرافیک |

🟡 = نصب‌شدنی است، ولی باید تست شود؛ ✅ = تأییدشده توسط پروژه یا بستهٔ بومی دارد.

### ۲٫۹ چک‌لیست تست یک اپ جدید

```sh
# ۱. نصب
linpad-get install ./app_arm64.deb

# ۲. اجرا از ترمینال (خطا را ببینید)
app-name

# ۳. اگر کتابخانه کم بود
env -u LD_PRELOAD /lib/ld-linux-aarch64.so.1 --list /usr/bin/app-name | grep 'not found'

# ۴. اگر Electron بود
app-name --no-sandbox

# ۵. بعد از موفقیت: Restart Desktop Session و اجرا از آیکون
```

---

## بخش ۳ — دستورهای کپی-پیست

```sh
# --- آماده‌سازی مهمان ---
linpad-get doctor
linpad-get island

# --- بستهٔ بومی (همیشه اول این) ---
apk search -v <name> && apk add <name>

# --- .deb ---
linpad-get install ./<file>_arm64.deb

# --- AppImage / tar ---
linpad-get install ./<file>.AppImage
linpad-get install ./<file>.tar.gz

# --- Electron ---
/usr/bin/<app> --no-sandbox

# --- X11 ---
printf '<app> x11\n' >> /etc/ishwl/apps

# --- عیب‌یابی کتابخانه ---
env -u LD_PRELOAD /lib/ld-linux-aarch64.so.1 --list /usr/bin/<app> | grep 'not found'

# --- حذف ---
linpad-get list
linpad-get remove <name>
```

---

## بخش ۴ — ریسک‌ها

| ریسک | شدت | کاهش |
|---|---|---|
| گواهی ۷ روزه و soft-ban اپل | بالا (عملیاتی) | SideStore برای refresh، یا حساب پولی |
| iloader روی iPadOS 27.2 پشتیبانی رسمی ندارد | متوسط | بخش ۱٫۶ |
| نصب `.deb` فایل سیستمی را عوض کند | متوسط | محافظ `apk info -W` در `linpad-get`؛ backup قبل از هر چیز |
| اپ Electron حافظه را پر کند | متوسط | Performance overlay، `Close apps when memory runs out` |
| Alpine 3.21 منقضی | بالا | مهاجرت به 3.24 (گزارش قبلی، بخش ۳٫۳) |
| حذف اپ با uninstall کردن LinPad | بالا | دادهٔ لینوکس با uninstall از بین می‌رود؛ backup بگیرید |

---

## بخش ۵ — منابع

- [iloader — سایت رسمی](https://iloader.site/) · [راهنمای نصب IPA](https://iloader.site/guides/install-ipa-iphone/) · [FAQ](https://iloader.site/faq/) · [GitHub](https://github.com/nab138/iloader)
- [LinPad v1.5.0 release](https://github.com/fspecii/LinPad/releases/tag/v1.5.0) · [فایل IPA](https://github.com/fspecii/LinPad/releases/download/v1.5.0/LinPad-1.5.0.ipa)
- [StikDebug](https://github.com/StikDebug/StikDebug) · [SideStore docs](https://docs.sidestore.io)
- [Alpine packages](https://pkgs.alpinelinux.org/packages) · [Debian package search](https://packages.debian.org/search?searchon=contents)
- داخل مخزن: `personalize/linpad-get`، `devtools/install-vscode.sh`، `devtools/debfetch.mjs`، `kernel/elf.h`، `kernel/fork.c`، `release/INSTALL-DEVICE.md`
