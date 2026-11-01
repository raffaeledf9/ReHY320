# 15 How install sessions work

Type: research
Status: resolved
Blocked by: 12

## Question

Ticket 12 decided the finished projector keeps USB debugging off and pulls files from a read-only share on the PC with its file manager. So:
1. How is that share set up on Windows with no third-party software: a dedicated local account, a read-only folder, which sharing settings, and how is it switched on only while transferring?
2. How does the projector connect to it with the file manager and hand an APK to the installer, driven by the remote?
3. Which permission does the file manager need to install apps, and how is that limited to it?
4. How is each APK's authenticity checked on the PC before it is put in the share?
5. The USB fallback: how an install from a stick works when the network route is unavailable.
6. When USB debugging is switched on for a PC install instead, how the session is opened, limited to this PC's key, and confirmed closed afterwards.

## Answer

Findings in [research/15-install-sessions.md](../research/15-install-sessions.md), 44 claims graded by an independent check.

The route works with nothing but Windows and the open-source file manager. A dedicated local account on the PC owns a read-only shared folder; the projector's file manager connects to it with that account, and the share is switched off between transfers. The modern protocol is used throughout, so the obsolete SMB1 does not have to be turned on anywhere. The projector needs no fixed address for this, and if the share is gone it says so plainly rather than looking like a permission problem.

Password-protected sharing stays on. The file manager can connect as a guest or anonymously, so leaving sharing open to everyone would expose the folder to anything on the network; the dedicated account is what keeps it narrow.

To install an app, the projector's file manager opens the APK and hands it to Android's own installer, which needs one permission granted once to the file manager alone. On this kind of firmware that switch is under "Security and restrictions", called "Unknown sources", not where a phone would have it.

Each APK's signature is checked on the PC before it goes into the share, with the certificate compared against the published one, as ticket 05 set out.

The USB stick remains the offline fallback, and switching USB debugging on for a PC install remains possible, limited to this PC's key and confirmed closed afterwards.

Small checks the runbook carries: that the share's permissions list only the dedicated account, that the firewall rule is scoped to the home network, and, in the last install session, where that "Unknown sources" switch actually is on this unit before reaching for a fallback.

## Amended after the user asked about a network path (2026-10-22)

The user asked whether the projector's storage could instead appear as network storage, so files are uploaded from the PC with a network path. Facts that decided it:
- A real `\projector\...` share is not possible without root: the port it needs is privileged and Android does not let an unrooted app listen there. Without root a network path means FTP or WebDAV on a high port, which Explorer handles clumsily and, for plain FTP, unencrypted.
- Any such path means a file server listening on the projector, which is what this project has been removing.
- Android's own USB file transfer (MTP) gives the same drag-and-drop from Explorer with no network service at all. This unit has the component (`com.android.mtp`) but it is **disabled**, and the USB port is configured for debugging only (`sys.usb.config=adb`).

**Decided: both routes, and no file server.**
1. **Over Wi-Fi, the projector pulls** from the read-only share on the PC, as above. Used for apps and occasional files.
2. **Over the cable, drag-and-drop**: the MTP component is enabled and the USB configuration includes it, so plugging the cable shows the projector in Explorer as a device to drag files onto. Used for bulk media.

They use different paths, neither opens anything on the network, and APKs still have their signature checked on the PC first. The port still cannot serve a USB stick and the PC at the same time, so the cable route is a deliberate session like the install sessions.

To settle in the runbook: whether the USB configuration can carry both file transfer and debugging at once on this build, and whether enabling the component is enough or the vendor also has to stop forcing debugging-only.
