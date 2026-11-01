# 10 Approve the keep-list

Type: grilling
Status: resolved
Blocked by: 09

## Question

Does the user accept the proposed keep-list, including every vendor part kept for a feature and every feature lost?

## Answer

The keep-list in [research/09-sort-components.md](../research/09-sort-components.md) is approved, with these decisions on the undecided items (user, 2026-10-20):

1. **Vendor settings app** (`com.htc.htcsettings`): removed, but only after ticket 19's own app provides keystone and projection orientation and the user has confirmed both work. The runbook must install and verify the replacement first. If orientation turns out to exist only inside that app and cannot be reproduced, stop and bring the decision back to the user.
2. **Google components**: keep Play Services and the service framework. Keep the Play Store too and test whether it works on this uncertified device; remove it only if it does not. Their startup components, switched off by the vendor scripts we delete, are switched back on.
3. **Standby**: remove the vendor screensaver, but keep screensaver behaviour: a screensaver whose image the user can replace with their own, and a timeout the user can change, defaulting to 30 minutes. Claude picks the default screensaver image. This goes into ticket 19's app (as an Android screensaver) and is specified in ticket 22.
4. **Small helpers**: keep both the focus-motor helper (`com.htc.closedialog`) and the Netflix remote helper (`com.android.nfx`). Neither can reach the network.

Everything else follows the proposal: stock Android, Allwinner hardware support and the infrared remote stay; the vendor updaters, store, uploader, factory test apps, casting stack, office suite and bloat go, together with the root daemon, the silent installer, the two scripts that disable Google's protection, the USB customisation path, their startup files, and the five pre-authorised app names in the policy.
