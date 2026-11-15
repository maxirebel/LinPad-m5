# ساخت IPA با GitHub Actions (بدون مک)

> فایل: `.github/workflows/build-ipa.yml` · رانر: `macos-26` (Apple Silicon)
> خروجی: `LinPad-<version>-unsigned.ipa` — **بدون امضا**، برای امضا با iloader در زمان نصب

## چرا این مسیر

LinPad فقط روی میزبان **aarch64** بیلد می‌شود — در `meson.build:30-31` صریح آمده: «-Djit=enabled requires an arm64 guest on an aarch64 host». پس نه ویندوز و نه macOS اینتلی در VMware جواب نمی‌دهد. رانر macOS گیت‌هاب یک مک اپل سیلیکون اجاره‌ای است.

## چطور اجرا می‌شود

1. این مخزن را در GitHub خودتان fork یا push کنید (فایل workflow باید در `.github/workflows/` باشد).
2. تب **Actions** → **Build unsigned IPA** → **Run workflow**.
3. صبر کنید (بار اول ۳۰ تا ۶۰ دقیقه؛ بارهای بعد با کش ۱۰ تا ۲۰ دقیقه).
4. در پایین صفحهٔ همان اجرا، بخش **Artifacts** → `LinPad-unsigned-ipa` را دانلود کنید.
5. فایل IPA را به ویندوز/آیپد منتقل کنید و با **iloader** نصب کنید (iloader آن را با Apple ID شما امضا می‌کند).

پوش کردن یک تگ `v*` هم همین workflow را اجرا می‌کند.

## چه کاری می‌کند

| گام | جزئیات |
|---|---|
| Checkout | با ساب‌ماژول‌ها (`libapps`، `deps/libarchive`) |
| ابزارها | `brew install llvm lld meson ninja libarchive` + افزودن llvm/lld به PATH |
| GPU | `gpu/build-third-party.sh ios` (virglrenderer + MoltenVK) با کش |
| rootfs | دانلود `linpad-rootfs-1.5.0.tar.gz` رسمی (۶۲۲ مگابایت) + بررسی SHA-256 |
| Build | `xcodebuild` با `ISH_JIT_BUILD=enabled` و **امضا خاموش** |
| بسته‌بندی | کپی rootfs داخل `.app` → `Payload/` → zip → IPA |
| خروجی | artifact + فایل `.sha256` + لاگ بیلد |

## نکات مهم

- **بدون امضا است.** IPA بدون امضا فقط با ابزار سایدلود (iloader / SideStore / Sideloadly) نصب می‌شود؛ همان‌جا با Apple ID شما امضا و به گواهی ۷ روزه تبدیل می‌شود. `get-task-allow` را هم همان امضا اضافه می‌کند، پس JIT با StikDebug کار می‌کند.
- **entitlement افزایش حافظه** را ندارد، مگر سورس پچ‌شده (`personalize/app-m5.patch`) را push کنید **و** ابزار سایدلود شما آن را بپذیرد (AltStore 2.2+ قبول می‌کند).
- **مخزن عمومی:** دقیقه‌ها و فضای artifact رایگان است. **مخزن خصوصی:** سهمیهٔ رایگان ۵۰۰ مگابایت است و یک IPA ۶۰۰+ مگابایتی از آن رد می‌شود — در آن حالت artifact را با retention کوتاه‌تر بگیرید یا مخزن را عمومی کنید.
- **زمان:** بیلد GPU و اپ سنگین است؛ `timeout-minutes: 180` گذاشته شده.
- **اگر بیلد شکست خورد:** artifact به نام `build-log` را دانلود کنید؛ ۶۰ خط آخر در صفحه هم نمایش داده می‌شود.

## چه چیزی را عوض کنیم اگر لازم شد

| موضوع | کجا |
|---|---|
| نسخهٔ روت‌فاس | ورودی `rootfs_url` / `rootfs_sha256` / `rootfs_version` هنگام Run workflow |
| نسخهٔ Xcode | `runs-on: macos-26` → `macos-15` و … |
| امضای واقعی (اختیاری) | افزودن سکرت‌های گواهی/پروفایل و ایمپورت آن‌ها؛ فعلاً لازم نیست چون iloader امضا می‌کند |
