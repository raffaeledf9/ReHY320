# 20 Security settings of the cleaned system

Type: grilling
Status: resolved
Blocked by: 11, 23

## Question

Which of the projector's own security settings should change while cleaning, given each one's risk of breaking the hardware: switching the mandatory-access-control layer from logging to blocking, closing the open raw-storage access, and removing the five app names the policy pre-authorises?

## Answer (user, 2026-10-22)

1. **The mandatory-access-control layer (SELinux): later, once the cleaned system is stable.** Switching it from logging to blocking means rewriting the vendor's boot image, and the vendor's own code has never run with it on. It becomes its own step afterwards, with its own undo, so a failure to boot has only one possible cause.
2. **The open raw-storage access: closed as the final step.** The vendor leaves the whole storage readable and writable by any app (`/vendor/ueventd.rc` sets it to 0666). It is also how writes are verified by reading them back, so it stays open through the cleaning and closes as the last change before the projector joins the Wi-Fi.
3. **The five pre-authorised app names in the policy file: removed with the cleaning**, as already agreed in ticket 10. They grant system privileges to apps that are not installed, and nothing needs them.

## Consequence spotted while explaining this (2026-10-22)

Closing the raw-storage access also removes the only way this project has to read the projector's partitions back: the per-partition devices are root-only, fastboot cannot read, and the finished system has no root. So after that final step, integrity can no longer be checked from the PC, and the remedy for any doubt becomes writing the golden backup back.

Therefore the runbook must, immediately before closing that access:
1. Read every partition back and record the hashes of the **cleaned** system, next to the golden backup's own manifest.
2. State plainly that from then on, verification means comparing the device against those recorded hashes only if the access is temporarily reopened, which is itself a write.

## Revised after the user's questions (2026-10-22)

The user asked whether we could sign a cleaned system ourselves, whether the finished system could have root, and how to fix the read-back gap. Reading this unit's own verification data gave better answers, and two decisions changed.

**1. Verification is rebuilt with our own key (decided: yes).** The parameters to reproduce are standard and were read straight off the device's data: dm-verity version 1, SHA-1, 4096-byte data and hash blocks, error correction with 2 roots, salt `2dce9204…dddd7b3a`, hash tree and error-correction data appended directly after each filesystem. Sizes: system filesystem 1,028,796,416 with 8,110,080 of tree and 8,200,192 of error correction; vendor 113,328,128 / 901,120 / 909,312; product 318,095,360 / 2,510,848 / 2,539,520. The rebuilt data fits the same logical partitions with about 260 KB spare.

So the cleaned partitions get fresh hash trees and a verification partition carrying their root hashes, signed with a key we generate (Google's own `avbtool` does this; it is a single open-source Python file from AOSP).

**What this is and is not:** the bootloader does not check the verification partition's signature — that is exactly why the relaxed copy booted — so this is integrity checking, not a root of trust anchored in hardware. It catches storage decay and any change made by something that is not already root. It cannot stop an attacker who already owns the device from regenerating it. Every later change to the system must regenerate the trees and the verification partition, which the runbook scripts.

Undo if a rebuilt tree is wrong: the projector will not boot, and the relaxed verification partition goes back through fastboot (128 KB), or the original container (about six minutes).

**2. No root on the finished system, and the build stays non-debuggable.** Marking it debuggable would make `adb root` possible over USB, but it also marks every app debuggable, which streaming apps check for. That would risk the Netflix goal to gain what decision 3 provides anyway.

**3. The storage device becomes readable by the PC only (decided).** This replaces the earlier "close it as the final step". The vendor's line in `/vendor/ueventd.rc` grants every app read **and write** access to the whole storage (mode 0666); it becomes `0440 root shell`:
- apps on the projector: no access at all, which is better than the vendor's setting and better than leaving it open;
- the PC over USB debugging: read-only, so every partition can still be verified without root;
- nothing can write it; writes go through fastboot or recovery only.

This removes the gap noted above: integrity can be checked at any time, and the system also checks itself continuously through decision 1.
