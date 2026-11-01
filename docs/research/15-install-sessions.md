# 15 How install sessions work: findings

Researched 2026-10-22 from the web and from the project files only. Nothing was installed, nothing was changed on the PC, no device was touched. This is a written procedure, not an installation.

Every claim carries a confidence mark: **high** means read in official documentation or in source code; **medium** means a single first-party statement, an inference from source, or a sister-device report; **low** means a community report or my own inference with no source behind it.

Vocabulary note: [GLOSSARY.md](../../GLOSSARY.md) defines **install session** as "a bounded window in which the projector accepts ADB from the PC's key only". After ticket 12 that is only the *fallback* route (section 6 below). The normal route is a **transfer window**: a read-only share up on the PC for a few minutes, no ADB at all. The glossary term no longer covers the normal case. Flagged for the domain model; I did not edit the glossary or the ticket.

---

## Short answer

1. **The share.** One dedicated **standard local account** on the PC (not an administrator), one folder, one share whose *share* permission is **Read** for that account only. `New-SmbShare ... -ReadAccess` does it in one command, and `-Temporary` makes the share disappear at the next reboot by itself. The per-session on/off switch is `net user <name> /active:no` — a disabled account cannot authenticate at all, so the switch is stronger than removing the share. Scope the firewall rule to the projector's address once, as a standing restriction.
2. **The projector.** Material Files: **Add storage… → SMB server**. It scans the subnet and offers the PC by name, so there is little typing with a remote. Leave **Path** empty and it lists the shares. Opening the APK gives an **Install** action; the app copies the file to its own cache first and then hands it to Android's package installer, which shows its own confirmation.
3. **The install permission.** `REQUEST_INSTALL_PACKAGES`, which Android 8 and later gate **per app** as an app-op. On handheld Settings: **Apps → Special app access → Install unknown apps → Material Files → Allow from this source**. On TV-style Settings, which this unit probably has: **Security & restrictions → Unknown sources → Material Files**. Grant it for the session, revoke it after. The fallback (`appops`) needs ADB, so grant it while the install session of section 6 is still open.
4. **APK authenticity** is checked on the PC with `apksigner verify --verbose --print-certs` before the file goes in the share, against the pinned certificate digest. Procedure already settled in [research 05](05-netflix-and-app-sources.md) section 3; nothing changes, the file simply travels over SMB instead of ADB.
5. **USB stick.** Format **FAT32** (4 GiB cap per file); exFAT needs kernel 5.10 or newer, which this Allwinner BSP almost certainly is not. Same Material Files → Install path from the stick.
6. **USB debugging**, when it is needed: turn it on, connect over the A-to-A cable, authorise *this* PC's key only, install, turn it off, then verify from the PC that nothing answers on 5555.

**SMB1 is not needed and must stay off.** Material Files speaks SMB2/SMB3 only. The one thing SMB1 would buy (browsing the workgroup through the master browser) is already handled by Material Files' own subnet sweep.

**Do not turn on required signing or share encryption without testing them.** Windows 11 **Home** does not require SMB signing by default, so the default configuration simply works; an open Material Files issue reports errors when a server *enforces* signing or encryption.

---

## 1. The share on the Windows 11 PC

PC as recorded in [ticket 01](../decisions/01-charting-decisions.md): Windows 11 **Home**, build 22631 (23H2). Everything below is built into Windows; no third-party software.

### 1.1 The account

- **Create it through Settings:** Settings → **Accounts** → **Other users** → **Add account** → **"I don't have this person's sign-in information"** → **"Add a user without a Microsoft account"**. New accounts are not guaranteed to be standard, so check: Other users → open the account → **Account options** → **Change account type** → **Standard User**. **High.** [Microsoft: create a local user or administrator account](https://support.microsoft.com/en-us/windows/create-a-local-user-or-administrator-account-in-windows-20de74e0-ac7f-3502-a866-32915af2a34d)
- **Or in one line** from an elevated prompt: `net user hy320 * /add /fullname:"HY320 transfer"` (the `*` prompts for the password without echoing it). `net user` also has `/active:{yes|no}`, `/expires`, `/passwordchg` and `/times`. **High** for the command; **medium** that it behaves identically on the Home edition — `net.exe` ships in every edition, but the reference page is the Windows Server one. [Microsoft: net user](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/net-user)
- **The password must exist and must be long and random, used nowhere else.** With the **Password** authentication type, Material Files' SMB client refuses to proceed without a stored password: `Client.kt` throws `"No password found for $authority"`. **High.** [Client.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/Client.kt)
  That throw is only a *null* check, and it does **not** mean the app can only do authenticated access — the Guest and Anonymous types store an empty password and pass it happily. See 1.3.
  Why long and random: the share will be reached over NTLMv2, and Microsoft's own guidance is that "the session key itself is derived from your password, using a long, complex, nondictionary password enhances SMB signing and encryption". **High.** [Microsoft: SMB signing overview](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing-overview)
  And it will be stored on a **low-trust device**. Treat it as a credential that may leak: unique to this job, read-only, one folder. If the projector is ever suspected, change that one password and nothing else is affected.
- **Honest limit on Home:** there is no built-in policy editor on Windows 11 Home (`secpol.msc`, `gpedit.msc`, `lusrmgr.msc` are Pro-and-above), so there is no supported way to deny this account an interactive logon. It will appear on the sign-in screen. A standard account with a long random password is the practical mitigation. **Medium** — I found no Microsoft page that states the edition split outright; verify by trying to open `secpol.msc` on the PC.

### 1.2 The folder and the share

```powershell
# elevated PowerShell, once
New-Item -ItemType Directory C:\hy320-out
New-SmbShare -Name hy320 -Path C:\hy320-out `
             -ReadAccess hy320 `
             -FolderEnumerationMode AccessBased `
             -ConcurrentUserLimit 1 `
             -Temporary
```

- `-ReadAccess` "specifies which users are granted read permission to access the share". That much is **high**. [Microsoft: New-SmbShare](https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare)
  The part that matters more — that `hy320` ends up as the *only* entry — is **not** on that page. Two independent module authors document the behaviour: Microsoft's own `ComputerManagementDsc` help states that if all the access parameters are removed, `New-SmbShare` adds **Everyone with read access**, and that naming a member in any access parameter prevents it; `Carbon.SmbShare` says accounts not in a specified list lose their permissions, "including the default Everyone read access rule". So naming `-ReadAccess hy320` and nothing else should leave exactly one ACE, read-only. **Medium**, and cheap to settle: `Get-SmbShareAccess -Name hy320` right after creating it, which must show one row, `hy320 / Allow / Read`. If it also shows `Everyone`, remove it with `Revoke-SmbShareAccess -Name hy320 -AccountName Everyone`. [ComputerManagementDsc about_SmbShare](https://powershellgallery.com/packages/ComputerManagementDsc/9.1.0/Content/DSCResources/DSC_SmbShare/en-US/about_SmbShare.help.txt), [Carbon.SmbShare](https://www.powershellgallery.com/packages/Carbon.SmbShare/1.0.0/Content/Carbon.SmbShare.psm1)
- `-FolderEnumerationMode AccessBased`: "SMB doesn't display the files and folders for a share to a user unless that user has rights to access the files and folders." Off by default on new shares. **High.** Same page.
- `-ConcurrentUserLimit 1`: one client at a time. **High.** Same page.
- `-Temporary`: "the new SMB share is temporary and will not persist beyond the next restart of the computer". A free safety net — if the share is ever forgotten, a reboot removes it. **High.** Same page.
- Check it afterwards with `Get-SmbShare` and `Get-SmbShareAccess -Name hy320`. **High.** [Microsoft: SmbShare module](https://learn.microsoft.com/en-us/powershell/module/smbshare/)
- Use a plain share name. A `$` suffix only hides a share from browse lists; it is not an access control, and it would also stop the share appearing when Material Files lists the server's shares (section 2.3), forcing you to type the name by hand. **Medium.**
- **Do not** run `Set-SmbPathAcl` here. It "sets the ACL for the file system folder to match the ACL used by an SMB share" — which would leave the folder readable-only by `hy320` and strip your own write access, so you could not put files in it. **High** for what the cmdlet does ([SmbShare module](https://learn.microsoft.com/en-us/powershell/module/smbshare/)); **medium** for the consequence, which is my inference.
- **Optional second layer at the NTFS level.** A folder created directly under `C:\` inherits the root's ACL, which on a default Windows install grants **Authenticated Users** Modify on new subfolders and files. The *share* ACL still blocks writes over the network, but if you want both layers:
  `icacls C:\hy320-out /inheritance:r /grant "Administrators:(OI)(CI)F" /grant "%USERNAME%:(OI)(CI)F" /grant "hy320:(OI)(CI)RX"`
  **Medium** on the inherited-Modify claim — check with `icacls C:\` on the PC before deciding whether this line is needed.

### 1.3 Sharing and firewall settings

- **Network profile must be Private.** The "File and Printer Sharing" firewall rules apply to the private profile. Settings → Network & internet → Wi-Fi → the network's properties → Network profile type → **Private**. **Medium.**
- **Advanced sharing settings:** Settings, search **"manage advanced sharing settings"** → **Private networks**: turn on **File and printer sharing**. **High** for the path. [Microsoft: file sharing over a network in Windows](https://support.microsoft.com/en-us/windows/file-sharing-over-a-network-in-windows-b58704b2-f53a-4b82-7bc1-80f9994725bf)
  - **Network discovery**: only needed so that *your* PC can see others. Nothing in this plan needs it. Leave it off — the Microsoft article tells you to turn it on, and that is for Explorer's Network view, not for this. The projector's own discovery is a NetBIOS name query (section 2.2), which rides the File and Printer Sharing exception's UDP 137. If the projector's server list nevertheless comes up empty, the cheap fallbacks in order are: **Add manually** with the PC's IP (one extra field, no setting changed), then turning Network discovery on for **Private** only.
  - **Password protected sharing (All networks): leave it ON.** That Microsoft article tells consumers to turn it off; do not. With it off, Windows allows unauthenticated access, which is the whole thing we are avoiding. **Medium** (the article's instruction is explicit; the consequence is the documented meaning of the setting).
    **Corrected during verification:** an earlier draft argued "Material Files could not use it anyway, since it insists on a password". That is wrong. The app's Add-storage dialog offers **Guest** and **Anonymous** as well as **Password**, and for those two it builds credentials from smbj's `AuthenticationContext.guest()` (`"Guest"`, `new char[0]`) and `.anonymous()` (`""`, `new char[0]`) — an *empty* password, which passes the null check in `Client.kt`. So the app is perfectly capable of unauthenticated access; password protected sharing being on is what stops that, and it matters **more** for this reason, not less. **High.** [EditSmbServerFragment.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/storage/EditSmbServerFragment.kt), [AuthenticationContext.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/auth/AuthenticationContext.java)
- **Scope the rule to the projector, once.** The inbound SMB rule can be limited to a single remote address:
  ```powershell
  Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -RemoteAddress 192.168.1.<projector>
  ```
  `-RemoteAddress` "specifies that network packets with matching IP addresses match this rule", and accepts a single IPv4 address. **High.** [Microsoft: Set-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallrule)
  This is the single best hardening step here: with it in place, no other device on the home Wi-Fi can even reach port 445 on the PC. It is also the reason the projector needs a fixed address (section 7).
  Note the rule group also carries the NetBIOS rules the projector's server discovery uses (section 2.2), so scoping the whole group keeps discovery working for the projector and shut for everything else. Microsoft documents that the File and Printer Sharing exception opens **UDP 137 and 138 and TCP 139 and 445** to the addresses in the rule, and that its default scope is any computer on the network — which is the thing being fixed here. That the individual rules carry the display group name `File and Printer Sharing` is the only part I could not confirm from a current page; check it once with `Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | ft DisplayName, Enabled, Profile`, which also shows whether a scoped `-RemoteAddress` took. **Medium.** [Understanding shared folders and the Windows Firewall](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc731402(v=ws.10))

### 1.4 Switching it on and off between transfers

Pick **one** switch and use it every time. In order of how reliably it shuts the door:

| Switch | Command | What it closes | Verify with |
|---|---|---|---|
| **Account disabled** (recommended) | `net user hy320 /active:no` / `/active:yes` | That identity cannot authenticate at all. "If the user account isn't active, the user can't access resources on the computer." | `net user hy320` → "Account active: No" |
| Share removed | `Remove-SmbShare -Name hy320` / re-run `New-SmbShare` | The share. Port 445 stays open and the account can still authenticate. | `Get-SmbShare` |
| Sharing off | `Disable-NetFirewallRule -DisplayGroup "File and Printer Sharing"` | Ports 445/137/138/139 inbound on that profile. Also stops every other sharing use. | `Get-NetFirewallRule -DisplayGroup "File and Printer Sharing"` |

`/active` text is **high** ([net user](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/net-user)): "If the user account isn't active, the user can't access resources on the computer." That a disabled account is refused *over SMB* is now also **high**, from the client side: Material Files' own status map has an explicit `STATUS_ACCOUNT_DISABLED` entry, which only exists because SMB servers return it — and it surfaces as "access denied" on the projector. [ClientException.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/ClientException.kt)

Two more useful checks, both built in: **`Get-SmbSession`** "retrieves information about the SMB sessions that are currently established between the SMB server and the associated clients" — this is how you see whether the projector is connected right now — and **`Close-SmbSession`** "ends forcibly the SMB session". **High.** [SmbShare module](https://learn.microsoft.com/en-us/powershell/module/smbshare/)

A sensible transfer window, then, is four steps: `net user hy320 /active:yes` → pull on the projector → `Get-SmbSession` shows nothing left → `net user hy320 /active:no`.

### 1.5 SMB1: not needed, keep it off

- Material Files' SMB client is **SMBJ**, pinned at `com.hierynomus:smbj:0.11.5`. **High.** [app/build.gradle](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/build.gradle)
- SMBJ is an "SMB2/SMB3 client library for Java". Its default dialect list, in source, is `.withDialects(SMB_3_1_1, SMB_3_0_2, SMB_3_0, SMB_2_1, SMB_2_0_2)` — no SMB1 anywhere. **High.** [SmbConfig.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/SmbConfig.java), [smbj README](https://raw.githubusercontent.com/hierynomus/smbj/master/README.adoc)
- Material Files builds the client with `SMBClient()` and no custom config, so those defaults are what the projector will use. **High.** [Client.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/Client.kt)
- Windows 11 ships without the SMB1 server or client after a clean install, and Microsoft "strongly recommend against reinstalling SMBv1". **High.** [Microsoft: SMBv1 not installed by default](https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/smbv1-not-installed-by-default-in-windows), [Microsoft: protect SMB traffic from interception](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-interception-defense)
- The only place SMB1 would have helped is Material Files' *first* discovery path, which browses `smb://` through the elected master browser; the code's own comment says this fails on recent Windows with SMB1 disabled. Its second path (a NetBIOS sweep of the subnet) does not need SMB1 and will find the PC. **High.** [LanSmbServerListLiveData.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/storage/LanSmbServerListLiveData.kt)

### 1.6 Signing and encryption: leave the defaults

- Microsoft states the per-edition default plainly: "Windows 11, version 24H2 Enterprise, Pro, and Education require both outbound and inbound SMB signing… **Windows 11, version 24H2 Home edition doesn't require outbound or inbound SMB signing.**" This PC is Home and on 23H2, which is earlier still, so signing is supported but not required, and the connection will succeed on defaults. **High.** [Microsoft: control SMB signing behavior](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing)
- SMBJ's defaults are `withSigningRequired(false)` and `withEncryptData(false)`. **High.** [SmbConfig.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/SmbConfig.java)
- **Do not require them without testing.** Material Files issue #486, "[Feature Request] Support SMB `server signing` & `server smb encrypt`", is **still open** (opened 2021-04-01, last comment 2025-04-23): with `server signing = mandatory` or `server smb encrypt = required` in smb.conf, the app errors out, and several commenters report the same while other clients connect. The report is against Samba, not Windows. **Medium** for whether it bites a Windows server — but the pinned library backs it up: smbj 0.11.5 predates **0.12.0**'s "Support signing and sealing of NTLM authentication" and **0.14.0**'s "Add configuration option to disable signing", so the version in the app is on the wrong side of smbj's own signing work. **High** for the version split. [#486](https://github.com/zhanghai/MaterialFiles/issues/486), [smbj README](https://raw.githubusercontent.com/hierynomus/smbj/master/README.adoc)
  One new fact: #486's timeline now carries a 2026-07-07 commit from a contributor, "Add per-server SMB encryption option". It is **not** in Material Files' master resources — `strings.xml` has no encryption or signing string — so treat per-server encryption as not shipped, and re-check it against the v1.7.5 build actually installed. **Medium.**
  If the user wants to try it, `Set-SmbServerConfiguration -RequireSecuritySignature $true` (machine-wide) or `Set-SmbShare -Name hy320 -EncryptData $true` (this share only) are the switches, and `$false` is the undo. Try the share-only encryption first: it is the narrower change.
- **What the exposure actually is, without signing.** Microsoft's interception guidance is written for this case: signing and encryption are what stop an adversary-in-the-middle tampering with or reading the traffic. On a WPA2 home network, the realistic attacker is a device already on the LAN. What crosses the wire is the APK or media file you are deliberately pushing, plus an NTLMv2 exchange that could be captured and attacked offline — which is why the account's password is long, random, and used nowhere else, and why its only privilege is reading one folder. **High** for the mechanism ([SMB interception defense](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-interception-defense)); **medium** for the risk judgement.

### 1.7 Who can reach the share, honestly

- **Only `hy320` can reach `\\PC\hy320`.** No other account is in the share ACL. Confirm with `Get-SmbShareAccess -Name hy320`. **High.**
- **Any member of the local Administrators group can reach the PC's hidden administrative shares** (`C$`, `ADMIN$`, `IPC$`) over the same port, regardless of this share. That is exactly why the transfer account is a *standard* user. Confirm with `net share`, which lists them. **Medium** (standard Windows behaviour; no page quoted).
- **Guest is not a way in — but only because the PC says no, not because the projector cannot ask.** The local Guest account is disabled by default, and password protected sharing (1.3) is what refuses unauthenticated sessions. Material Files *can* ask: it offers Guest and Anonymous authentication (see the correction in 1.3), so the PC side is the only thing standing in the way. Microsoft's caveat that Windows 11 Home and Pro "allow guest authentication by default" sits in a section about disabling guest authentication *and fallback* on the SMB **client** ("SMB2 and SMB3 clients no longer allow guest account access…"), so it does not describe this PC acting as the server. **High.** [SMB interception defense](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-interception-defense)
- **Anything on the LAN can *attempt* to authenticate** while 445 is reachable. The firewall scope of section 1.3 removes that; the account switch of section 1.4 removes it too. Lockout is the backstop: Microsoft's security baselines recommend a threshold of 10 invalid attempts, and recent Windows 11 builds are widely reported to ship an account lockout policy enabled by default (10 attempts, 10 minutes). The baseline recommendation is **high** ([account lockout threshold](https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/account-lockout-threshold)); that it is on by default on *this* build is **low** — only secondary coverage of a Microsoft VP's announcement for Insider build 22528 ([SecurityWeek](https://www.securityweek.com/new-default-account-lockout-policy-windows-11-blocks-brute-force-attacks)). **Read the real value with `net accounts` on the PC.**
- **The direction of trust is the point.** The projector pulls; the share is read-only; nothing listens on the projector; no inbound port is opened to it. A compromised projector can read one folder on the PC and write nothing. That is the whole reason ticket 12 chose this shape over pushing files to the projector.

---

## 2. The projector side, driven by the remote

Material Files v1.7.5 from F-Droid, as settled in [research 13](13-launcher-and-file-manager.md). It registers both LAUNCHER and LEANBACK_LAUNCHER, so it appears as a TV app and opens from FLauncher.

### 2.1 Before the first transfer

Grant Material Files **All files access** (it declares `MANAGE_EXTERNAL_STORAGE`) and the install permission of section 3. **High** for the permission ([manifest](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/AndroidManifest.xml)); the exact Settings screens on this vendor firmware are a device check (research 13, open question 7).

### 2.2 Adding the share, once

Exact strings, read from the app's own resources, so these are the words on screen:

1. Open the navigation drawer → **"Add storage…"**
2. **"SMB server"**
3. The app shows **"Searching for SMB servers…"**, a list, and **"Add manually"**.
4. Pick the PC from the list, or **Add manually** and fill in:

| Field | Value |
|---|---|
| **Hostname** | the PC's IPv4 address, e.g. `192.168.1.x` (see section 7) |
| **Port** | leave empty, placeholder is **445** |
| **Path** | **leave empty** — "Can be left empty"; the app then lists the server's shares |
| **Name** | leave empty — "Use hostname" |
| **Authentication** | **Password** (the other entries are Guest and Anonymous) |
| **Username** | `hy320` |
| **Password** | the account's password |
| **Domain** | leave empty |

5. **"Connect and add"**.

**High** for the fields and wording. [strings.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/res/values/strings.xml)

How the search works, from source: SMBJ cannot browse the workgroup on modern Windows, so Material Files falls back to a **NetBIOS sweep of the local subnet** using jCIFS-NG's `nameServiceClient.getNbtAllByAddress(...)`, up to 60 lookups in parallel, and takes each reply's first NetBIOS hostname. It only does this when the device has a site-local IPv4 address — `192.168.1.0/24` qualifies. **High.** [LanSmbServerListLiveData.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/storage/LanSmbServerListLiveData.kt)

So the PC will appear by name in that list if NetBIOS over TCP/IP is on and the "File and Printer Sharing" firewall rules allow UDP 137 — which they do once section 1.3 is done. NetBIOS over TCP/IP being on is the default: the adapter's WINS setting is "Default", meaning take it from DHCP, and Microsoft states that "if the DHCP server does not send the Disable NetBIOS over TCP/IP (NetBT) DHCP option during DHCP lease negotiation … NetBIOS over TCP/IP is enabled". A consumer ASUS router does not send that option. **Medium-high.** [Disable NetBIOS over TCP/IP using DHCP](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/disable-netbios-tcp-ip-using-dhcp)
This is the one thing that keeps remote-control setup short: you pick the PC from a list and only type the username and password. If it does not work, **Add manually** with the IP costs one more field and changes nothing on the PC.

Typing a password with a remote is the slow part. It is typed **once**: the entry is saved, and later transfers are just "open the share". The character you cannot reach on the D-pad keyboard is the character to leave out of the password — favour length over exotic symbols.

### 2.3 Each transfer

1. On the PC: `net user hy320 /active:yes`.
2. On the projector: Material Files → the saved server → the share → the file.
3. Tap the APK. The behaviour of the **"Open Android package"** setting decides what happens; its three options are **"Install"**, **"View contents"** and **"Ask what to do"**. Set it to **Install** or **Ask what to do**. **High**, read in the app's own resources. [strings.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/res/values/strings.xml), [#1595](https://github.com/zhanghai/MaterialFiles/issues/1595)
4. Choose **Install**. What then happens, from source: `InstallApkJob` **copies the file into the app's own cache directory first** (`open_cache`, on external cache when mounted, otherwise the internal `cacheDir`), then builds an install intent from a `FileProvider` URI (Android 7+ path) and starts the installer. **High.** [FileJobs.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/filejob/FileJobs.kt)
   Two consequences worth knowing:
   - The 2022 report of APKs from removable media failing as invalid ([#822](https://github.com/zhanghai/MaterialFiles/issues/822), still open) is less likely to bite here, because the installer never sees the network path — it sees a local cache copy. **Medium**, inference from the code.
   - **Stay in Material Files while it copies.** The job hands off through `BackgroundActivityStarter` with a notification fallback — the strings are *"'%1$s' is ready to be installed"* / *"Tap to install"*. On a TV a notification is awkward to act on with a remote. If you navigate away mid-copy you may land on that path. **Medium**: the strings and the call are in source ([strings.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/res/values/strings.xml), [FileJobs.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/filejob/FileJobs.kt)); I could not read `BackgroundActivityStarter` to see exactly when the fallback triggers. Device check.
5. Android's package installer shows its own screen; confirm there. For the first install of an app, the certificate you pinned on the PC becomes the one Android will demand for every later update: "The system allows the update if the certificates match." **High.** [Android: sign your app](https://developer.android.com/studio/publish/app-signing)
6. On the PC: `Get-SmbSession` empty, then `net user hy320 /active:no`.

For media files rather than APKs, the same share works — but a large film streamed over Wi-Fi from a share that is only up during transfers is not the plan; copy it to the projector's storage or use the stick.

---

## 3. The install permission, and keeping it to one app

- **What Material Files needs:** `REQUEST_INSTALL_PACKAGES`, which it declares, plus a handler for `application/vnd.android.package-archive`. **High.** [manifest](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/AndroidManifest.xml)
- **The gate is per app, since Android 8.** Each installing app needs the user's own "Install unknown apps" grant; there is no global "unknown sources" switch any more. **High.** [Android Developers blog](https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html)
- **It is an app-op, not a runtime permission.** AOSP android11-release declares it `android:protectionLevel="signature|appop"`, with the comment "Apps targeting APIs greater than 25 must hold this permission in order to use `Intent#ACTION_INSTALL_PACKAGE`". The `appop` flag is exactly why the `appops` fallback below works. **High.** [core/res/AndroidManifest.xml (android11-release)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/AndroidManifest.xml)
- **The screen, phone/tablet Settings:** Settings → **Apps** → **Special app access** → **Install unknown apps** → pick the app → **"Allow from this source"**. **High** for the path on stock handheld Android. [Google: download apps to your Pixel phone](https://support.google.com/pixelphone/answer/7391672)
- **The screen, TV Settings — expect this one first.** This unit reports a fake Google ADT-3 identity ([ticket 07](../decisions/07-identify-and-inventory.md)) and runs a leanback launcher, so it most likely carries the **TV** Settings app, where the screen is named differently: section **"Security & restrictions"** → **"Unknown sources"** → *"Allow installation of apps from sources other than the Play Store"*, which lists the installed apps one by one, then a confirmation **"Allow unknown sources"** / *"Your device and personal data are more vulnerable to attack by apps from unknown sources."* Those are AOSP TvSettings' own strings on the android11 branch (`system_security`, `security_unknown_sources_title`, `security_unknown_sources_desc`, `security_unknown_sources_confirm_title`). **High** for the AOSP TV strings; **medium** that this vendor kept them. [TvSettings strings.xml (android11-release)](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/values/strings.xml). Sony's own TV help guide shows the same screen reached as Settings → Privacy → Security & Restrictions → Unknown sources, which is how vendors reshuffle it. [Sony help guide](https://helpguide.sony.net/tv/nusltn2/v1/en-003/contents/TP1002006251.html)
  So: **look under "Security & restrictions" before concluding the grant is impossible.** Only if neither screen exists does the `appops` route below become the only way.
- **This is already the limit.** The permission is held by one app, named by the user, and nothing else on the projector can install. Revoke it with the same toggle after the session. Android also warns developers to re-check `canRequestPackageInstalls()` because users change it at any time. **High.** [Android: publish your app](https://developer.android.com/studio/publish)
- **Two device checks carried from research 13:**
  - Whether this vendor's Settings has **either** screen — "Security & restrictions → Unknown sources" (the TV name) or "Apps → Special app access → Install unknown apps" (the handheld name). If neither, the grant has to go through `adb shell appops set me.zhanghai.android.files REQUEST_INSTALL_PACKAGES allow` — which needs ADB, so **do it while the install session of section 6 is open**, before USB debugging goes off for good. (Research 13, open question 7.)
  - Whether `com.android.packageinstaller` is present and unmodified, and whether the vendor's `preinstall` / `appsdisable` binaries block installs from non-whitelisted installers. It has to stay on the keep-list. (Research 13, open question 8.)

---

## 4. Checking an APK's authenticity on the PC, before it goes in the share

Unchanged from [research 05](05-netflix-and-app-sources.md) section 3. Nothing about SMB alters it — the file is verified on the PC and then copied into a folder, exactly as it would have been verified and then pushed with `adb install`. In short:

1. `apksigner verify --verbose --print-certs file.apk` (Android SDK Build-Tools on Windows, not WSL's `apksigner` 0.9, which cannot check v3). Pass means no error, a `true` for the v2 and/or v3 scheme, and exactly one signer. Note `Signer #1 certificate SHA-256 digest`.
2. Compare that digest with the source's published value and with an older version of the same app. `apksigner` prints lowercase hex without colons; websites usually show uppercase with colons. Any mismatch stops the install.
3. Pin the digest in the project files. Android enforces the same rule from the first install onwards.
4. `Get-FileHash file.apk -Algorithm SHA256` against the download page's hash only proves the transfer.
5. Refuse any APK signed with the AOSP public test key DN.

**One addition that belongs to this ticket:** verify **before** the file goes in the share, not after. The share is read-only to the projector, so once a file is in it the projector will take whatever is there; the gate is the PC-side check. And nothing from the projector ever travels the other way: the share grants no write access, which is what keeps [ticket 01](../decisions/01-charting-decisions.md)'s "nothing from the projector ever runs on the PC" rule intact for this route. **High** (project decision).

Sources for the above, all from research 05: [apksigner](https://developer.android.com/tools/apksigner), [app signing](https://developer.android.com/studio/publish/app-signing), [Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash), [AOSP test keys README](https://android.googlesource.com/platform/build/+/refs/heads/main/target/product/security/README).

---

## 5. The USB-stick fallback

Used when the PC is off, the network is down, or the share will not connect.

- **Format FAT32.** AOSP's `vold` has both `Vfat.cpp` and `Exfat.cpp`, but exFAT needs kernel support — AOSP's kernel filesystem list marks `exfat` as kernel **5.10 and later** — plus `/system/bin/mkfs.exfat` and `/system/bin/fsck.exfat` present. An Allwinner H713 BSP kernel is very unlikely to be 5.10. NTFS support was removed from `vold`. So FAT32 (`vfat`) is the one format to rely on. **Medium-high**: the AOSP facts are high, the kernel version on this unit is a device check (`adb shell uname -r`, or Settings → About). [AOSP: kernel file system support](https://source.android.com/docs/core/architecture/android-kernel-file-system-support), [vold fs/](https://android.googlesource.com/platform/system/vold/+/main/fs)
- **FAT32's cost:** maximum file size `2^32 - 1` bytes, i.e. just under 4 GiB. Fine for every APK in this project (the largest noted in research 05 is 67 MB); a problem for a long film. **High.** [Microsoft: maximum volume sizes](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-2000-server/cc938432(v=technet.10))
- **Formatting on Windows:** the built-in format tool creates FAT32 volumes up to **32 GB**. Careful with the citation: the quoted sentence is "32 GB (This is due to the **Windows 2000** format utility…)" on an archived Windows-2000-era page, so it documents the limit's origin, not today's build. That the limit is still in Windows 11's format dialog is the well-known behaviour and the premise of the Q&A thread below, but it is **inference, not a current Microsoft statement** — check it on the PC by opening Format on the actual stick. A stick of 32 GB or less formats from File Explorer; above that, expect Windows not to offer FAT32. A 2 TB FAT32 limit was shown in an Insider Canary build; there is no official confirmation it reached a released build. **High** for the 32 GB limit, **low** for the 2 TB change. [Microsoft: maximum volume sizes](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-2000-server/cc938432(v=technet.10)), [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/3980111/how-do-i-format-a-400gb-usb-drive-in-fat32-on-wind)
- **The steps:** verify the APK on the PC (section 4) → copy it to the stick → **the projector's USB debugging must be off, or the port will not read the stick** (ticket 12's whole reason) → plug the stick in → Material Files → the stick → the APK → **Install**.
- **Known snag, weaker than it looked:** [#822](https://github.com/zhanghai/MaterialFiles/issues/822) (open, opened 2022-07-02) reports an APK on removable media installing as corrupted — but on a **micro SD card**, on a Sony Xperia M4 running **Android 6.0.1**, which is before the FileProvider path the app uses on Android 7+, and the maintainer never found a cause. Waiting a few seconds on the installer dialog before pressing Install worked for the reporter. The source now copies to cache first (section 2.3). Very unlikely to apply to Android 11 here. If it bites anyway: copy the APK from the stick to internal storage first, then install from there. **Low.**
- Nothing about the stick route is read-only: a stick that has been in the projector has been writable by it. Keep one stick for this job, and treat anything the projector wrote on it as the projector's data, not the PC's.

---

## 6. When USB debugging is used instead

The route for anything SMB cannot do: `appops` grants, `pm` commands, a `--user 0` install, a multi-APK bundle (`adb install-multiple`), or recovering from a broken file manager. It is the glossary's **install session**.

### 6.1 Opening it

1. Physically connect the **USB-A to USB-A** link described in [ticket 03](03-usb-access-without-network.md): the user's USB-A to USB-C cable plus a USB-C (female) to USB-A (male) adapter, into a PC USB-A port.
2. On the projector: Settings → About → tap **Build number** seven times → Developer options → **USB debugging** on. (The vendor's Settings layout may differ; device check.)
3. `adb devices` on the PC.

### 6.2 Limiting it to this PC's key

- The projector must have **only this PC's public key** in `/data/misc/adb/adb_keys`, and `ro.adb.secure=1` so that authentication is actually enforced. Both are already researched in [02b, key `wifiadb`](02b-planning-facts-data.json): `adbd` skips authentication entirely on a debuggable build or an unlocked device unless `ro.adb.secure` is explicitly 1, and its default is false — so a missing property means **no** authentication. **High** (read in `adb/daemon/main.cpp`, android11-release).
- Pre-seed the key *before* enforcing, so you cannot lock yourself out, and set `adb_allowed_connection_time` to 0 so the key is not dropped after a week unused. Commands in 02b.
- **Negative test, each time it matters:** stop the ADB server, rename `%USERPROFILE%\.android` aside, `adb connect`/reconnect, expect **unauthorized** plus an on-screen prompt, deny it, then restore the folder. **High** (the mechanism), **medium** (that this vendor's SystemUI even has the prompt — 02b's open question: check `adb shell pm dump com.android.systemui` for `.usb.UsbDebuggingActivity`; if it is missing, an un-seeded key can never be approved and the pre-seeded key is mandatory).

### 6.3 Closing it, and proving it closed

1. Turn **USB debugging** off in Developer options.
2. Developer options → **Revoke USB debugging authorizations** (clears accepted keys; it does not remove a hand-seeded `adb_keys` entry).
3. Unplug the cable.
4. `adb kill-server; adb devices` on the PC → empty.
5. **From the PC, check nothing answers on the network:** `Test-NetConnection 192.168.1.<projector> -Port 5555` must fail. This step is not optional. 02b found, in `adbd`'s own source, that when no port property is set **and** there is no USB FFS endpoint, `adbd` still listens on TCP 5555 — confirmed: `if (access(USB_FFS_ADB_EP0, F_OK) == 0) { usb_init(); is_usb = true; }`, then the port properties, then `} else if (!is_usb) { addrs.push_back("tcp:" DEFAULT_ADB_LOCAL_TRANSPORT_PORT) }`.
   **Narrowed during verification:** that is a statement about `adbd` *once it is running*. With USB debugging off, init normally never starts `adbd` at all, so in the ordinary case "debugging off" does shut 5555 — the source finding is the failure mode, not the default. It still has to be tested here, because this firmware shipped with a preset open network debugging port ([ticket 12](../decisions/12-final-system-shape.md)), which means vendor init starts `adbd` on its own terms; and because `service.adb.listen_addrs` overrides all of the above when set. Read that property too. Whether `/dev/usb-ffs/adb/ep0` exists on this unit is an open device question. The comparable real case is CVE-2026-30495, an Optoma projector with unauthenticated ADB on 5555. **High** for the source reading, **open** for this unit. [adbd main.cpp (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/android11-release/adb/daemon/main.cpp), [CVE-2026-30495](https://cveawg.mitre.org/api/cve/CVE-2026-30495)
6. Record in the runbook that the window is closed.

**Network debugging is never used.** Ticket 12 settled this: the cleaning removes the preset open port and it is not re-enabled. An install session is USB-only, and the projector's single USB port being busy is exactly why it is a session and not a standing state.

---

## 7. Two things the ticket asked for on top

### 7.1 Does the projector need a fixed address?

**Not for SMB itself.** The projector is the client; it dials out. Nothing needs to know where it is.

**Yes, for two other reasons:**

1. **If you scope the firewall rule to it** (section 1.3, and you should — it is the single biggest reduction in exposure), the rule names an IP, so that IP must not move.
2. [Research 16](16-probation-tooling.md) already requires fixed addresses for both the PC and the projector, for the router's connection log: "`MAC=` is printed only on the input path … That is why the projector needs a fixed IP."

**What *does* need a stable address is the PC**, because that is what Material Files connects to. Three options:

- **Bind the PC's address at the router** — Advanced Settings → **LAN → DHCP server** → **Enable Manual Assignment** = Yes, enter the MAC and an IP inside the pool, click **+**, then **Apply**. The device itself stays on "obtain an IP automatically", and the address **must be inside the DHCP pool** ("Please make sure the IP address needs to be in the IP pool of your DHCP server"). **High** for the path and the pool rule. The "32 entries" figure is *not* on that page — ASUS says the maximum varies by model and is shown on the router's own DHCP server page; treat 32 as unconfirmed and read the real number there. [ASUS FAQ 1000906](https://www.asus.com/support/faq/1000906/), and already written up in research 16 section 4.
- **Rely on Material Files' NetBIOS discovery** (section 2.2) and re-pick the PC if its address changes. Workable, one extra step per change.
- **Use the PC's name instead of its IP.** `Client.kt` does resolve a hostname and prefers IPv4, so the field accepts a name. But Android has no NetBIOS name resolver, so a bare `PC-NAME` will not resolve, and `.local` depends on mDNS behaviour I did not verify on either side. **Low** — do not plan on it. [Client.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/Client.kt)

**One binding is not enough.** Android 11 joins each Wi-Fi network with its own randomized MAC, stable until a factory reset (research 16). Research 16's binding is for the **guest SSID** used during probation; moving to the home Wi-Fi means a **second, different** MAC and so a second binding. Expect to add it at the move, not before. **Medium** (high for stock Android behaviour; the vendor must actually have randomization enabled — device check).

### 7.2 What the user sees if the share is unavailable

From `ClientException.kt`, Material Files maps SMB status codes to Java file-system exceptions and keeps the original message, then shows that message:

| Situation | What surfaces |
|---|---|
| PC off, unreachable, or the firewall blocking | Not an SMB status at all, so a plain `FileSystemException` carrying the underlying Java network error text — "Connection refused", "Network is unreachable", a socket timeout |
| Account disabled, wrong password, no permission | `STATUS_LOGON_FAILURE`, `STATUS_ACCOUNT_DISABLED`, `STATUS_PASSWORD_EXPIRED`, `STATUS_ACCESS_DENIED`, `STATUS_SHARING_VIOLATION`, `STATUS_PRIVILEGE_NOT_HELD`, `STATUS_LOGON_TYPE_NOT_GRANTED`, `STATUS_USER_SESSION_DELETED` all become **`AccessDeniedException`** |
| **Share removed** (corrected) | `STATUS_BAD_NETWORK_NAME` / `STATUS_NETWORK_NAME_DELETED` / `STATUS_BAD_NETWORK_PATH` → **`NoSuchFileException`**, not access-denied. So "the share is gone" and "the account is switched off" look *different* on screen, which is useful: a not-found message means check `Get-SmbShare`, an access-denied message means check `net user hy320` |

**High** for the mapping. [ClientException.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/ClientException.kt)

**It may take a while before it says anything.** SMBJ's defaults are a **60-second** read/write/transact timeout and `soTimeout = 0`, meaning **no socket timeout**. So a PC that is off can leave the folder apparently hanging rather than failing fast. **High** for the values. [SmbConfig.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/SmbConfig.java)

Practical consequence for the user: *the saved server entry never disappears and never warns you*. It simply does not open, after a pause. That is the right behaviour for this design — the share being absent is the normal state — but it means "the projector can't see the PC" and "I forgot to enable the account" look identical from the sofa. The habit that fixes it: enable on the PC first, and if the folder does not open within a minute, check `net user hy320` and `Get-SmbShare` on the PC before touching anything on the projector.

---

## 8. Alternatives considered

| Route | Verdict |
|---|---|
| **SMB share, read-only, account-switched** | **Chosen.** Everything built into Windows and into the file manager that is already going on the projector. Nothing new listens on the projector. One command to open, one to close. |
| **SFTP via Windows' own OpenSSH Server** | Real alternative, and encrypted, with `Stop-Service sshd` as a clean switch and no port 445 exposure. Material Files has an SFTP client (`sshj:0.40.0`) and an "SFTP server" entry in Add storage. Against it: OpenSSH Server is an optional feature to install, not present by default; it needs `sshd_config` editing to be SFTP-only (`ChrootDirectory` is supported on Windows **only** for SFTP sessions, and needs `ForceCommand internal-sftp`); without that the transfer account gets a shell; and read-only still has to come from NTFS, not from SSH. More moving parts for the same result. **High** on the Windows OpenSSH facts. [Microsoft: OpenSSH server configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration), [build.gradle](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/build.gradle) |
| **A plain HTTP server on the PC** (`python -m http.server`) | Simplest possible server and genuinely read-only, but Material Files mounts SMB, SFTP, FTP and WebDAV — not HTTP — and the deployed projector has no browser. Dead end for this file manager. **Medium.** |
| **LocalSend, or any push tool** | Rejected in 02b: it opens a listener on the projector, which is the opposite of what ticket 12 decided, and it has open Android TV bugs (#249 OK button cannot confirm, #1264 remote control, #3335 APK install failing on an HY350max projector). |
| **ADB over the network** | Never. Ticket 12: the preset open port is removed by the cleaning and is not re-enabled. |

---

## Open questions — only the device or the PC can answer these

**On the PC (read-only checks, nothing changes):**

1. `net accounts` — the real account lockout threshold and duration on this build. Section 1.7 relies on it as the backstop and I could only find secondary sources for the default.
2. `icacls C:\` — whether a new folder under `C:\` really inherits **Authenticated Users: Modify**, which decides whether the optional `icacls` line in section 1.2 is worth running.
3. Whether `secpol.msc` opens on this Home edition. If it does, "deny log on locally" for the transfer account becomes available and section 1.1's honest limit goes away.
4. `Get-SmbServerConfiguration | fl RequireSecuritySignature, EnableSMB1Protocol` — the actual starting point before anything is changed.
5. The PC's own name as NetBIOS reports it, since that is what the projector's discovery list will show.

**On the projector (inside an install session, before USB debugging goes off):**

6. Which of the two install-permission screens this vendor firmware has: **Security & restrictions → Unknown sources** (the TV Settings name, most likely here) or **Apps → Special app access → Install unknown apps** (the handheld name). If neither, grant `REQUEST_INSTALL_PACKAGES` to Material Files with `appops` while ADB is still available — there is no second chance once debugging is off. (Research 13, open question 7.)
7. Whether `com.android.packageinstaller` is present and unmodified, and whether the vendor's `preinstall`/`appsdisable` binaries refuse installs from a non-whitelisted installer. (Research 13, open question 8.)
8. `uname -r` — the kernel version, which decides whether exFAT is even possible on the stick, or whether FAT32's 4 GiB file cap is permanent.
9. Whether `/dev/usb-ffs/adb/ep0` exists. If it does not, `adbd` falls back to TCP 5555 whenever no port property is set, and section 6.3 step 5 becomes the only thing standing between "debugging off" and an open port.
10. Whether this SystemUI has `.usb.UsbDebuggingActivity`. Without it the "Allow USB debugging?" prompt never appears and the pre-seeded key is the only way in.
10b. `getprop ro.boot.verifiedbootstate ro.adb.secure ro.debuggable` **after** ticket 20's revised step rebuilds verification with the project's own key. Ticket 12's amendment of 2026-10-22 changes the verified-boot state the projector reports, and `adbd` skips authentication on an "unlocked" state unless `ro.adb.secure` is explicitly 1 — section 6.2 sets it explicitly for exactly this reason, so the plan holds either way, but the value should be read again once verification is back on.
11. Whether Material Files' SMB server list actually finds the PC with a remote, and whether the install hand-off launches the installer directly or drops to the "Tap to install" notification (section 2.3).
12. The projector's MAC on the **home** SSID, for the second DHCP binding, and whether MAC randomization is enabled at all on this vendor build.

**Not resolvable from the sources I read:**

13. Whether Material Files issue [#486](https://github.com/zhanghai/MaterialFiles/issues/486) still applies with smbj 0.11.5 against a *Windows* server that requires signing. The issue is open, but it is five years old and tested against Samba. The only way to know is to set `Set-SmbShare -Name hy320 -EncryptData $true`, try, and set it back. Worth one experiment, in its own step, with the undo written down — if it works, the traffic is encrypted and section 1.6's residual risk disappears.

---

## Verification table

| # | Claim | Status | Source |
|---|---|---|---|
| 1 | Material Files' SMB client is `com.hierynomus:smbj:0.11.5`; it also carries `sshj:0.40.0`, `dcerpc:0.12.13`, `jcifs-ng:2.1.10`, `dav4jvm` | Confirmed | [app/build.gradle](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/build.gradle) |
| 2 | SMBJ default dialects are SMB 3.1.1 / 3.0.2 / 3.0 / 2.1 / 2.0.2 — no SMB1; `signingRequired` and `encryptData` both default false; timeout 60 s; `soTimeout` 0 (none) | Confirmed, read in source | [SmbConfig.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/SmbConfig.java) |
| 3 | Material Files creates the client as `SMBClient()` with no custom config, so those defaults apply; it requires a password; it prefers IPv4 when a host resolves to several addresses | Confirmed | [Client.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/Client.kt) |
| 4 | SMBJ is an "SMB2/SMB3 client library for Java"; its README changelog shows signing work in 0.12.0 and a disable-signing option in 0.14.0, both *after* the pinned 0.11.5 | Confirmed | [smbj README](https://raw.githubusercontent.com/hierynomus/smbj/master/README.adoc) |
| 5 | Material Files #486, "support SMB server signing & server smb encrypt", is still **open** (2021-04-01, updated 2025-04-23); the app errors when a Samba server enforces signing or encryption | Confirmed open; applicability to Windows unverified | [#486](https://github.com/zhanghai/MaterialFiles/issues/486) |
| 6 | Add-SMB-server fields and wording: Hostname, Port (placeholder 445), Path ("Can be left empty"), Name ("Use hostname"), Authentication {Password, Guest, Anonymous}, Username, Password, Domain, "Connect and add"; the list screen says "Searching for SMB servers…" with "Add manually" | Confirmed | [strings.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/res/values/strings.xml) |
| 7 | Server discovery is a jCIFS-NG NetBIOS sweep of the site-local IPv4 subnet (`getNbtAllByAddress`, up to 60 threads); the `smb://` master-browser path is noted in the code as failing on recent Windows with SMB1 disabled | Confirmed | [LanSmbServerListLiveData.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/storage/LanSmbServerListLiveData.kt) |
| 8 | `InstallApkJob` copies the APK into the app's `open_cache` directory first, then starts the installer with a FileProvider URI on Android 7+ | Confirmed | [FileJobs.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/filejob/FileJobs.kt) |
| 9 | A "ready to be installed / Tap to install" notification exists as the background fallback | Strings confirmed; trigger condition not read | [strings.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/res/values/strings.xml) |
| 10 | SMB errors map to Java exceptions keeping the original message; logon/session/access/sharing/privilege → `AccessDeniedException`; deleted network name → `NoSuchFileException` | Confirmed | [ClientException.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/ClientException.kt) |
| 11 | `New-SmbShare` has `-ReadAccess`, `-FolderEnumerationMode AccessBased` (off by default), `-ConcurrentUserLimit`, `-EncryptData`, and `-Temporary` ("will not persist beyond the next restart") | Confirmed | [New-SmbShare](https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare) |
| 12 | `Get-SmbSession`, `Close-SmbSession`, `Get-SmbShareAccess`, `Remove-SmbShare`, `Set-SmbPathAcl` all exist in the built-in SmbShare module | Confirmed | [SmbShare module](https://learn.microsoft.com/en-us/powershell/module/smbshare/) |
| 13 | "Windows 11, version 24H2 Home edition doesn't require outbound or inbound SMB signing"; Pro/Enterprise/Education 24H2 require both | Confirmed, exact sentence | [control SMB signing behavior](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing) |
| 14 | Windows 11 ships with no SMB1 server or client after a clean install; Microsoft strongly recommends against reinstalling it; unused SMB1 components are auto-removed after 15 days | Confirmed | [SMBv1 not installed by default](https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/smbv1-not-installed-by-default-in-windows) |
| 15 | SMB signing/encryption is what defends against interception; "Windows 11 Home and Pro … allow guest authentication by default" (client side) | Confirmed | [SMB interception defense](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-interception-defense) |
| 16 | `Set-NetFirewallRule -RemoteAddress` accepts a single IPv4 address and restricts which packets match; `-DisplayGroup` applies the change to a whole predefined group | Confirmed, with example | [Set-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallrule) |
| 17 | Local-account creation path: Settings → Accounts → Other users → Add account → "I don't have this person's sign-in information" → "Add a user without a Microsoft account"; account type changed under Account options | Confirmed | [create a local account](https://support.microsoft.com/en-us/windows/create-a-local-user-or-administrator-account-in-windows-20de74e0-ac7f-3502-a866-32915af2a34d) |
| 18 | `net user` supports `/add`, `/active:{yes|no}` ("if the user account isn't active, the user can't access resources on the computer"), `/expires`, `/passwordchg`, `/times`; `*` prompts for the password | Confirmed | [net user](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/net-user) |
| 19 | Advanced sharing settings path in Windows 11, and the names of the Private / All networks toggles | Confirmed; its advice to disable password-protected sharing is deliberately **not** followed here | [file sharing over a network](https://support.microsoft.com/en-us/windows/file-sharing-over-a-network-in-windows-b58704b2-f53a-4b82-7bc1-80f9994725bf) |
| 20 | Account lockout: baselines recommend 10 invalid attempts; official default values table shows 0 (no lockout) for client GPO defaults | Confirmed as written; the "on by default in current Windows 11" claim rests only on secondary coverage | [account lockout threshold](https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/account-lockout-threshold), [SecurityWeek](https://www.securityweek.com/new-default-account-lockout-policy-windows-11-blocks-brute-force-attacks) |
| 21 | FAT32: maximum file size `2^32 - 1` bytes; the Windows format utility creates volumes up to 32 GB | Confirmed (archived Microsoft page) | [maximum volume sizes](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-2000-server/cc938432(v=technet.10)) |
| 22 | A FAT32 limit of 2 TB in the format dialog appeared in an Insider Canary build; no official confirmation it shipped | Unverified | [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/3980111/how-do-i-format-a-400gb-usb-drive-in-fat32-on-wind) |
| 23 | AOSP `vold` handles vfat and exFAT; exFAT is listed against kernel 5.10+ and needs `mkfs.exfat`/`fsck.exfat`; NTFS support was removed from `vold` | Confirmed for AOSP; this unit's kernel unverified | [kernel file system support](https://source.android.com/docs/core/architecture/android-kernel-file-system-support), [vold fs/](https://android.googlesource.com/platform/system/vold/+/main/fs) |
| 24 | Android 8+ gates installs per app ("Install unknown apps" / "Allow from this source"); apps must re-check `canRequestPackageInstalls()` | Confirmed | [Android Developers blog](https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html), [publish your app](https://developer.android.com/studio/publish), [Pixel help](https://support.google.com/pixelphone/answer/7391672) |
| 25 | Android allows an update only if the signing certificates match | Confirmed | [app signing](https://developer.android.com/studio/publish/app-signing) |
| 26 | Windows OpenSSH supports `ChrootDirectory` "only with SFTP sessions", with `ForceCommand internal-sftp`; only `password` and `publickey` authentication are available | Confirmed — corrects my own prior assumption that chroot was unsupported on Windows | [OpenSSH server configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration) |
| 27 | `adbd` on android11 skips authentication unless `ro.adb.secure` is explicitly 1, and falls back to TCP 5555 when no port property is set and there is no USB FFS endpoint | Confirmed in 02b from source | [adbd main.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/android11-release/adb/daemon/main.cpp), [02b `wifiadb`](02b-planning-facts-data.json) |
| 28 | ASUS manual IP assignment: Advanced Settings → LAN → DHCP server → Enable Manual Assignment → MAC + IP inside the pool → + → Apply; the device stays on automatic | Confirmed, and already in research 16 | [ASUS FAQ 1000906](https://www.asus.com/support/faq/1000906/) |

### Corrections made during verification

- **"Windows OpenSSH does not support ChrootDirectory."** Wrong. It has been supported since v7.7.0.0 for SFTP sessions. SFTP is therefore a genuine alternative, not a dead end; it is rejected in section 8 on setup cost, not on capability.
- **"Windows 11 24H2 requires SMB signing, so the share may break after an update."** Too broad. The requirement is per edition, and Home does not require it. The real risk for this PC is the opposite direction: signing is *not* required, so the traffic is unsigned unless deliberately changed.
- **"Material Files may fail to install an APK read from removable or network media (#822)."** Softened. The source copies the file into its own cache before handing it to the installer, so the installer never sees the remote path. The report stays as a low-confidence snag with a known workaround.
- **"A `$` share name helps."** Removed as a security claim. It hides the share from browse lists only, and would make the projector's share listing miss it.

---

## Verification

Independent check, 2026-10-22, by a second reader whose job was to break the claims above. Every cited source was opened again; where a claim could be attacked from a second direction, it was. Nothing was run, no device was touched, nothing on the PC was changed. **Three claims were refuted or materially narrowed and are fixed in place above** — marked *(fixed in place)* below.

Legend: **confirmed** = the source says it, in those words or unmistakably; **partly** = true with a limit the text did not state; **refuted** = wrong, now corrected; **unverified** = no source found either way, must be read off the PC or the projector.

### A. The Windows share

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| A1 | `New-SmbShare -ReadAccess` grants read permission to the named users | **confirmed** | Verbatim. [New-SmbShare](https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare) |
| A2 | …and therefore no other account is in the share ACL at all | **partly** *(fixed in place)* | Not on the Microsoft page. Microsoft's `ComputerManagementDsc` help says `New-SmbShare` adds **Everyone: Read** when *all* access parameters are omitted, and that naming any member prevents it; `Carbon.SmbShare` says named lists strip "the default Everyone read access rule". Consistent with the claim, but second-hand. Section 1.2 now says to confirm with `Get-SmbShareAccess` and how to fix it if `Everyone` shows up. [about_SmbShare](https://powershellgallery.com/packages/ComputerManagementDsc/9.1.0/Content/DSCResources/DSC_SmbShare/en-US/about_SmbShare.help.txt) |
| A3 | `-FolderEnumerationMode AccessBased`: "SMB doesn't display the files and folders for a share to a user unless that user has rights"; off by default | **confirmed** | Verbatim, and "The default value is `Unrestricted`" / "By default, access-based enumeration is disabled for new SMB shares". Same page |
| A4 | `-ConcurrentUserLimit 1` = one client at a time | **confirmed** | "maximum number of concurrently connected users"; 0 means unlimited and is the default. Same page |
| A5 | `-Temporary` → the share is gone after the next restart | **confirmed** | "the new SMB share is temporary and will not persist beyond the next restart of the computer. By default, new SMB shares aren't temporary." Same page |
| A6 | `net user <name> /active:no` stops that identity authenticating | **confirmed** | Verbatim: "Enables or disables the user account. If the user account isn't active, the user can't access resources on the computer. The default is **yes**." `/add`, `*` to prompt for the password, `/expires`, `/passwordchg`, `/times` all confirmed too. [net user](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/net-user) |
| A7 | …and SMB specifically refuses a disabled account | **confirmed** (upgraded from medium) | Attacked from the client side instead: Material Files' own status map has an explicit `STATUS_ACCOUNT_DISABLED` → `AccessDeniedException` entry, which exists only because servers return it. [ClientException.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/ClientException.kt) |
| A8 | Advanced sharing settings path, and the Private / All networks toggle names | **confirmed** | Search Settings for "manage advanced sharing settings" → Private networks → File and printer sharing; All Networks → password protected sharing; and "if you're on a Wi-Fi network … set it to Private". The article does tell consumers to turn password protected sharing **off**, which this plan deliberately does not do. [file sharing over a network](https://support.microsoft.com/en-us/windows/file-sharing-over-a-network-in-windows-b58704b2-f53a-4b82-7bc1-80f9994725bf) |
| A9 | "Material Files could not use unauthenticated sharing anyway, since it insists on a password" | **refuted** *(fixed in place)* | The app offers **Guest** and **Anonymous** in the Add-storage dialog and builds them from smbj's `AuthenticationContext.guest()` = `("Guest", new char[0], null)` and `.anonymous()` = `("", new char[0], null)`. An empty password is not a null password, so `Client.kt`'s "No password found" check never fires for them. The *advice* (leave password protected sharing on) survives and gets stronger; the argument for it was wrong. Same correction applied to 1.7's guest bullet. [EditSmbServerFragment.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/storage/EditSmbServerFragment.kt), [AuthenticationContext.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/auth/AuthenticationContext.java) |
| A10 | `Set-NetFirewallRule -RemoteAddress` restricts which packets match, and takes one IPv4 address | **confirmed** | Verbatim: "Specifies that network packets with matching IP addresses match this rule", with "Single IPv4 Address: 1.2.3.4" among the accepted formats. `-DisplayGroup`: "all of the rules or sets in that group receive the same set of modifications". [Set-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallrule) |
| A11 | The File and Printer Sharing rules carry the NetBIOS ports the projector's discovery needs | **partly** *(note added)* | Microsoft documents that the exception opens **UDP 137, 138 and TCP 139, 445** and that its default scope is any computer on the network — the thing being fixed here. That the individual rules sit in a display group literally named `File and Printer Sharing` is not on a current page; one `Get-NetFirewallRule -DisplayGroup` run settles it. [Understanding shared folders and the Windows Firewall](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc731402(v=ws.10)) |
| A12 | NetBIOS over TCP/IP is on by default, so the projector's sweep finds the PC | **confirmed** (strengthened) | "If the DHCP server does not send the Disable NetBIOS over TCP/IP (NetBT) DHCP option during DHCP lease negotiation or TCP/IP is manually configured, NetBIOS over TCP/IP is enabled." The adapter's WINS tab default means take it from DHCP. [Disable NetBIOS over TCP/IP using DHCP](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/disable-netbios-tcp-ip-using-dhcp) |
| A13 | "Windows 11, version 24H2 Home edition doesn't require outbound or inbound SMB signing" | **confirmed** | Exact sentence, in a list that also names Pro/Enterprise/Education 24H2 as requiring both. Worth knowing: the same page elsewhere says signing "is required by default on the latest Insider Preview builds of Windows 11", so the edition list is the specific statement and the Insider line the loose one. [control SMB signing behavior](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing) |
| A14 | The long-password quote ("the session key itself is derived from your password…") | **confirmed** | It is on `smb-signing-overview`, exactly as quoted — a real page, not a mis-citation. The same page adds "Don't connect to shares by using IP addresses … otherwise NTLM is used instead of Kerberos", which is this plan's situation by design. Microsoft's interception page separately urges "15 characters or more". [SMB signing overview](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing-overview) |
| A15 | Windows 11 ships with no SMB1 server or client after a clean install; don't reinstall it | **confirmed** | "Windows 11 doesn't contain the SMBv1 server or client by default after a clean installation", and "We strongly recommend that you don't reinstall SMBv1." The 15-day auto-removal applies to Windows 10 in-place upgrades, not to this PC. [SMBv1 not installed by default](https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/smbv1-not-installed-by-default-in-windows) |
| A16 | Windows 11 Home/Pro "allow guest authentication by default" is about the client, not the server | **confirmed** | The sentence sits inside "Disable guest authentication and fallback", whose subject is explicitly the SMB *client* ("SMB2 and SMB3 clients no longer allow guest account access or fallback"). The report's reading is right. [SMB interception defense](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-interception-defense) |
| A17 | No policy editor on Windows 11 Home, so no "deny log on locally" for the transfer account | **unverified** | No official Microsoft page states the edition split. Microsoft Q&A answers (community, not Microsoft) agree gpedit/secpol are Pro and above and warn against third-party installers for Home. Confidence stays as written; open question 3 settles it. |
| A18 | A new folder under `C:\` inherits Authenticated Users: Modify | **unverified** | Matches the documented default root-ACL pattern but no page states it for Windows 11. Open question 2 (`icacls C:\`) is the test; the optional `icacls` line is harmless either way. |
| A19 | Windows 11 ships an account lockout policy (10 attempts / 10 minutes) | **unverified**, with a new reason to doubt it here | Secondary coverage agrees it arrived with Insider build 22528, but one write-up adds that the defaults **apply to clean installs only** and are not applied retroactively to upgraded systems. Microsoft's own policy page still lists a default of 0. So `net accounts` is not optional if the lockout backstop is being relied on. [Specops: default account lockout policies in Windows 11](https://specopssoft.com/blog/default-account-lockout-policies-in-windows-11), [account lockout threshold](https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/account-lockout-threshold) |

### B. Does an Android file manager need SMB1? No.

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| B1 | Material Files' SMB client is smbj, pinned at 0.11.5 | **confirmed** | Also `sshj:0.40.0`, `dcerpc:0.12.13`, `jcifs-ng:2.1.10`, `ftpserver-core:1.2.1`, `dav4jvm` at a commit hash. [app/build.gradle](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/build.gradle) |
| B2 | smbj is SMB2/SMB3 only; defaults are 3.1.1 / 3.0.2 / 3.0 / 2.1 / 2.0.2, no SMB1 | **confirmed** | The README's own one-liner is "SMB2/SMB3 client library for Java"; the builder default is `.withDialects(SMB_3_1_1, SMB_3_0_2, SMB_3_0, SMB_2_1, SMB_2_0_2)`. There is no SMB1 dialect to select. [SmbConfig.java](https://raw.githubusercontent.com/hierynomus/smbj/master/src/main/java/com/hierynomus/smbj/SmbConfig.java), [README](https://raw.githubusercontent.com/hierynomus/smbj/master/README.adoc) |
| B3 | Material Files uses those defaults (`SMBClient()`, no config) | **confirmed** | `private val client = SMBClient()`, no `SmbConfig`. Also confirmed: hostname resolution prefers the first `Inet4Address`. [Client.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/provider/smb/client/Client.kt) |
| B4 | signing and encryption default off in smbj; 60 s operation timeout; no socket timeout | **confirmed** | `withSigningRequired(false)`, `withEncryptData(false)`, `DEFAULT_TIMEOUT = 60` seconds for read/write/transact, `DEFAULT_SO_TIMEOUT = 0`. Same source as B2 |
| B5 | The only thing SMB1 would buy is workgroup browsing, and the app's fallback does not need it | **confirmed** | The code tries `SmbFile("smb://").listFiles()` and its own comment records that this fails on recent Windows with SMBv1 disabled (`ERROR_SERVICE_NOT_INSTALLED`), noting Windows moved to WS-Discovery, which has no good Java implementation. It then sweeps the subnet with `nameServiceClient.getNbtAllByAddress(...)` on a 60-thread pool, guarded by `localAddress is Inet4Address && isSiteLocalAddress`. NetBIOS name service is not SMB1. [LanSmbServerListLiveData.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/storage/LanSmbServerListLiveData.kt) |
| B6 | Do not *require* signing or encryption without testing; #486 is open | **confirmed, and better supported than the text claimed** | #486 is open (2021-04-01, last comment 2025-04-23); the failure is against **Samba** with `server signing = mandatory` / `server smb encrypt = required`, and others report the same while iOS Files and cifs-utils connect. Independent corroboration in smbj's own changelog: **0.12.0** adds "Support signing and sealing of NTLM authentication" and **0.14.0** adds "Add configuration option to disable signing" — both *after* the pinned 0.11.5. New fact: #486's timeline carries a 2026-07-07 commit "Add per-server SMB encryption option", but master's `strings.xml` has no encryption or signing string, so treat it as not shipped. Noted in 1.6. [#486](https://github.com/zhanghai/MaterialFiles/issues/486) |
| B7 | The add-SMB-server fields and the on-screen wording | **confirmed** | "Add storage…", "SMB server", "Searching for SMB servers…", "Add manually", Hostname, Port (placeholder 445), Path (placeholder "Can be left empty"), Name ("Use hostname"), Authentication {Password, Guest, Anonymous}, Username, Password, Domain, "Connect and add". [strings.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/res/values/strings.xml) |
| B8 | The APK-open setting is "Open Android packages" with View / Install / Ask | **partly** *(fixed in place)* | The real strings are the setting **"Open Android package"** and the options **"Install"**, **"View contents"**, **"Ask what to do"**. Trivial, but 2.3 sells these as the words on screen, so they are now the words on screen. Same source as B7 |
| B9 | `InstallApkJob` copies the APK to its own cache first, then hands a FileProvider URI to the installer | **confirmed** | `Paths.get(cacheDirectory.path, "open_cache")`, external cache when mounted else internal, `copy(...)` with `replace = true`, early return if the copy fails, then `file.fileProviderUri` on API 24+ (`Uri.fromFile` below N) and `BackgroundActivityStarter.startActivity(...)`. The "ready to be installed" / "Tap to install" strings exist; the exact trigger condition still unread. [FileJobs.kt](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/java/me/zhanghai/android/files/filejob/FileJobs.kt) |
| B10 | SMB errors keep the original message; logon/access/sharing/privilege → `AccessDeniedException`; a removed share → `AccessDeniedException` | **partly** *(fixed in place)* | The access-denied list is confirmed and longer than stated (`ACCESS_DENIED`, `SHARING_VIOLATION`, `PRIVILEGE_NOT_HELD`, `LOGON_FAILURE`, `PASSWORD_EXPIRED`, `ACCOUNT_DISABLED`, `OPLOCK_NOT_GRANTED`, `CANNOT_DELETE`, `LOGON_TYPE_NOT_GRANTED`, `USER_SESSION_DELETED`, `FILE_ENCRYPTED`, `NETWORK_SESSION_EXPIRED`). But a **removed share** returns `STATUS_BAD_NETWORK_NAME`, which maps to **`NoSuchFileException`**, not access-denied. Good news, and 7.2 now says so: the two failure modes are distinguishable from the sofa. A non-SMB cause (PC off) falls through to a generic `FileSystemException` carrying the Java network message, as stated. Same source as A7 |

### C. The Android 11 install permission

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| C1 | The permission is `REQUEST_INSTALL_PACKAGES` and Material Files declares it | **confirmed** | Declared, alongside `MANAGE_EXTERNAL_STORAGE`, `QUERY_ALL_PACKAGES`, `INTERNET`, `POST_NOTIFICATIONS` and others. The `application/vnd.android.package-archive` filter is on `FileListActivity` (action VIEW — the archive-viewer filter, which is why the "Open Android package" setting of B8 exists), and `LEANBACK_LAUNCHER` is on its launcher filter, as research 13 said. [AndroidManifest.xml](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/AndroidManifest.xml) |
| C2 | It is gated per app by the user since Android 8, with no global switch | **confirmed**, now from AOSP itself | android11-release declares `<permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" … android:protectionLevel="signature\|appop" />` with the comment "Apps targeting APIs greater than 25 must hold this permission in order to use `Intent#ACTION_INSTALL_PACKAGE`". The `appop` flag is the formal basis for both the user toggle and the `appops set … allow` fallback. [core/res/AndroidManifest.xml (android11-release)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/AndroidManifest.xml) |
| C3 | The screen is Settings → Apps → Special app access → Install unknown apps | **partly** *(fixed in place)* — right path, wrong device class | That is the **handheld** path. On a TV build the same control is in AOSP TvSettings under the section **"Security & restrictions"** (`system_security`) as **"Unknown sources"** (`security_unknown_sources_title`), described as "Allow installation of apps from sources other than the Play Store", with a confirmation "Allow unknown sources". Since this unit reports a fake ADT-3 identity and runs leanback, that is the likelier screen; section 3 now names both and says to look there before concluding the grant is impossible. Sony's TV help guide shows a vendor-reshuffled variant (Settings → Privacy → Security & Restrictions → Unknown sources). [TvSettings strings.xml (android11-release)](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/values/strings.xml), [Sony help guide](https://helpguide.sony.net/tv/nusltn2/v1/en-003/contents/TP1002006251.html) |
| C4 | Android allows an update only if the signing certificates match | **confirmed** | "When the system is installing an update to an app, it compares the certificate(s) in the new version with those in the existing version. The system allows the update if the certificates match." And a different certificate requires a different package name, i.e. a separate app. This is what makes the pinned digest of section 4 bind for every later update. [app signing](https://developer.android.com/studio/publish/app-signing) |

### D. USB stick and the ADB fallback

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| D1 | exFAT needs kernel 5.10 or later | **confirmed** | AOSP states `exfat` is "supported in kernel 5.10 and later". The *userspace tools* requirement (`mkfs.exfat` / `fsck.exfat`) is **not** on that page — it comes from `vold`, so it stays at medium. [kernel file system support](https://source.android.com/docs/core/architecture/android-kernel-file-system-support) |
| D2 | `vold` carries vfat and exFAT; NTFS was removed | **confirmed** | `system/vold/fs` on main contains exactly `Exfat`, `Ext4`, `F2fs`, `Vfat` (.cpp/.h). No `Ntfs`. [vold fs/](https://android.googlesource.com/platform/system/vold/+/main/fs) |
| D3 | FAT32's file-size cap is just under 4 GiB | **confirmed** | "Maximum file size: 2^32 − 1 bytes". [maximum volume sizes](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-2000-server/cc938432(v=technet.10)) |
| D4 | The Windows format tool stops at 32 GB for FAT32 | **partly** *(fixed in place)* | The limit is real but the parenthesis actually reads "This is due to the **Windows 2000** format utility" — an archived Windows-2000 page, so it does not establish today's dialog. Section 5 now flags this as inference and says to check the Format dialog on the actual stick. The 2 TB Insider change stays **unverified**, as written. Same page |
| D5 | `adbd` falls back to TCP 5555 when no port property is set and there is no USB FFS endpoint | **confirmed in source, narrowed in meaning** *(fixed in place)* | Confirmed: `if (access(USB_FFS_ADB_EP0, F_OK) == 0) { usb_init(); is_usb = true; }`, then `service.adb.tcp.port` / `persist.adb.tcp.port`, then `} else if (!is_usb) {` push `tcp:DEFAULT_ADB_LOCAL_TRANSPORT_PORT`. Two things the text did not say: `service.adb.listen_addrs` **overrides all of it** when set, and none of it applies unless `adbd` is running — with USB debugging off, init normally never starts it. So "debugging off ⇒ 5555 shut" is usually true; the source finding is the failure mode. The test in 6.3 step 5 stays, because this firmware shipped a preset open debugging port. [adbd main.cpp (android11-release)](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/android11-release/adb/daemon/main.cpp) |
| D6 | `adbd` skips authentication unless `ro.adb.secure` is explicitly 1, on a debuggable build or an unlocked device | **confirmed** | `bool device_unlocked = "orange" == GetProperty("ro.boot.verifiedbootstate", "")`; then `if (__android_log_is_debuggable() \|\| device_unlocked) { auth_required = GetBoolProperty("ro.adb.secure", false); }` — a missing property reads **false**. Setting it explicitly, as 6.2 does, is the right move. Same page |
| D7 | The comparable real case, CVE-2026-30495 | **confirmed** | Optoma CinemaX P2 projector, Android 8.0.0: the record says the device "exposes Android Debug Bridge (ADB) on TCP port 5555 over the network without requiring authentication" and "is configured with ro.adb.secure=0, which disables RSA key verification", plus a working `su`. CWE-285, CVSS 3.1 base 8.8. An exact precedent for this class of device. [CVE-2026-30495](https://cveawg.mitre.org/api/cve/CVE-2026-30495) |
| D8 | #822: an install from removable media can fail as invalid | **partly** *(fixed in place)* | Open, but much narrower than presented: a **micro SD card** on a Sony Xperia M4 running **Android 6.0.1** — before the FileProvider path — titled "Unable to Install .apk files stored in external storage due to It becomes corrupted", with no cause found and the wait-a-few-seconds workaround. Downgraded to **low** in section 5. [#822](https://github.com/zhanghai/MaterialFiles/issues/822) |

### E. The alternatives, and the fixed address

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| E1 | Windows OpenSSH supports `ChrootDirectory` for SFTP only, with `ForceCommand internal-sftp`; only password and publickey auth | **confirmed** | "ChrootDirectory (support added in v7.7.0.0) — This directive is only supported with SFTP sessions. A remote session into cmd.exe doesn't honor ChrootDirectory. To set up a sftp-only chroot server, set ForceCommand to internal-sftp." And "For Windows OpenSSH, the only available authentication methods are `password` and `publickey`." The earlier self-correction in this file was right. [OpenSSH server configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration) |
| E2 | ASUS manual DHCP assignment: Advanced Settings → LAN → DHCP server → manual assignment → MAC + IP → + → Apply | **confirmed**, with one correction *(fixed in place)* | Path confirmed, and the FAQ adds a rule the text omitted: "Please make sure the IP address needs to be in the IP pool of your DHCP server." The **"32 entries"** figure is *not* on that page — ASUS says the maximum varies by model and is shown on the router's own DHCP page. Softened above. [ASUS FAQ 1000906](https://www.asus.com/support/faq/1000906/) |
| E3 | The projector needs a fixed address for the scoped firewall rule and for research 16's log mapping | **confirmed as reasoning** | Follows from A10 (the rule names one IP) plus research 16. Unchanged. |

### What was changed in this file

1. **Sections 1.1, 1.3 and 1.7** — removed the refuted claim that Material Files cannot use unauthenticated sharing. It can: Guest and Anonymous pass an empty password. The recommendation (password protected sharing stays ON) is unchanged and now rests on the right reason.
2. **Section 3, the short answer, and open question 6** — added the Android **TV** Settings path ("Security & restrictions → Unknown sources"), sourced to AOSP TvSettings on the android11 branch, because this unit is a leanback device and the handheld path may simply not exist. Added the AOSP `signature|appop` protection level, which is what the `appops` fallback rests on.
3. **Section 7.2** — a removed share surfaces as *not found*, not *access denied*. The two failure modes are distinguishable after all; the table and the closing advice now say so.
4. **Section 1.2** — the "only `hy320` in the ACL" step carries its real (second-hand) sourcing, a one-line check, and the fix if `Everyone` appears.
5. **Sections 1.3 and 2.2** — added what Microsoft actually documents about the File and Printer Sharing ports, the NetBIOS-over-TCP/IP default, and the cheap fallback if the projector's server list comes up empty.
6. **Section 1.4** — "a disabled account is refused by SMB" upgraded to high with a client-side source.
7. **Section 1.6** — the don't-enable-signing advice now cites smbj's own changelog, which puts the signing work after the pinned version.
8. **Section 2.3** — the APK-open setting's real strings.
9. **Section 5** — #822 downgraded to low with its real context (Android 6, SD card); the FAT32 32 GB citation flagged as a Windows-2000-era page.
10. **Section 6.3** — the 5555 claim kept but narrowed: it describes `adbd` while running, and `service.adb.listen_addrs` overrides everything.
11. **Section 7.1** — the ASUS entry limit softened; the in-pool rule added.

### Still only answerable on the PC or the projector

Every item in the original open-questions list stands. Verification added or sharpened these:

- `Get-SmbShareAccess -Name hy320` immediately after creating the share — one row, or is `Everyone` there too (A2).
- `Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | ft DisplayName, Enabled, Profile` — does the group name resolve, and did `-RemoteAddress` take (A11).
- `net accounts` — this matters more than the original text implied: the Windows 11 lockout defaults are reported to apply to **clean installs only** (A19).
- Open the Format dialog on the actual USB stick — does Windows 11 still cap FAT32 at 32 GB (D4).
- On the projector, **look under "Security & restrictions → Unknown sources" first**, then under Apps → Special app access (C3).
- `getprop service.adb.listen_addrs ro.adb.secure ro.boot.verifiedbootstate` alongside the 5555 test (D5, D6).
- Whether the installed Material Files v1.7.5 carries a per-server SMB encryption option that master's resources do not (B6).
