# Could a newer Android go on this projector?

Asked on 2026-10-22, after the cleaning was built: since so much is being rebuilt anyway, could the projector run a newer and still-supported Android? Investigated without agents, from this unit's own data plus Google's documentation.

**Answer: technically it could be attempted, it would reach Android 12 at best, and it would cost every projector-specific function. Not worth doing on this device.**

## What the device would allow

In its favour, this unit is a proper Treble device, which is what a generic Android image needs:
- dynamic partitions, with a separate vendor partition and its own verification partition;
- vendor interfaces at Keymaster 4.1, past the version that blocks generic images;
- it launched on Android 11 (`ro.product.first_api_level` 30), so its vendor side is Android 11-era.

Against it, and decisively for how far it could go:
- **The userspace is 32-bit only.** `ro.product.cpu.abilist64` is empty and the system starts the 32-bit app runtime alone. Google's generic images do include a 32-bit ARM target, but all current ones are built from the Android 12 codebase, and nothing in Google's own documentation offers a 32-bit ARM image for Android 13 or later. So Android 12 is the realistic ceiling: one version up, itself no longer receiving security updates.
- 1 GB of memory, which a newer Android uses more of than Android 11 does.
- Nobody appears to have run a generic image on an H713 projector; the community work on this chip is all Android 11 firmware or a separate Linux port.

## Why it would break the projector

A generic image replaces **the whole system partition**. On this projector that is exactly where the projector lives, which we know from reading its own files:

| What it does | Where it lives | After a generic image |
|---|---|---|
| Keystone, automatic keystone, projection mode | the patched framework in the system partition | gone |
| The actual picture warping | a display library used by the display server, also in system | gone |
| The focus motor on the remote's keys | the patched framework | gone |
| The infrared remote service | a program in the system partition | gone |
| HDMI input | three Allwinner apps in the system partition | gone |

The vendor partition survives a generic image, so the drivers would stay, but the vendor put this projector's behaviour in the **system** half, not the vendor half. The apps could be copied back; the framework patches could not, because a framework belongs to its Android version.

So a newer Android would give a cleaner, more current system that cannot correct keystone, cannot focus, probably cannot be driven by its own remote, and cannot show HDMI. For a projector that is not an upgrade.

## What is worth doing instead

The parts that are actually attacked in practice are not the kernel: they are the browser engine, the Google components and the apps. Those can all be current on Android 11:
- **The browser engine** (`/product/app/webview`) is an ordinary updatable component; a current build can be installed like any app, and it is what renders untrusted content.
- **Google Play Services** updates itself once online, independently of the Android version.
- **Every app** we install is current, and the projector keeps nothing listening except AirPlay.

That gives a device whose exposed surface is up to date, on a kernel that is not. Combined with what the runbook already does — no vendor network services, nothing listening, the storage closed to apps, verification rebuilt — it is a better outcome than a generic image that breaks the hardware.

## The honest long-term answer

If the goal is a projector running a currently supported operating system, it is not this one: it is a small streaming box on the HDMI input, with the projector as a display. That decision was already taken for Google Cast, and the same reasoning applies here.

A separate possibility, for later and for curiosity rather than for use: the community port of mainline Linux to this chip. It is not Android, so it runs no apps, it was verified only on a sibling model, and it is beta. Noted, not recommended.
