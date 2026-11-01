# 18 Can an own app set keystone and orientation

Type: research
Status: resolved
Blocked by: 08

## Question

On this unit's golden backup, analysed offline on the PC: can an ordinary app (or one signed like the vendor's own system apps) set manual keystone corners and projection orientation, the way the stock launcher's screens do, and which permissions or calls does it need? Confirms or corrects ticket 04 for this unit.

## Answer

Yes, almost certainly, and more simply than expected. Findings in [research/18-own-app-keystone-access.md](../research/18-own-app-keystone-access.md).

Keystone is done by the graphics system through `libkeystone.so`, and the four corners are plain system properties (`persist.display.keystone_*`) that Android stores and restores by itself. An own app only has to set eight properties, with no special interface. The screens that do this today are in the vendor **settings** app, not the launcher, so removing the launcher costs nothing here; removing the vendor settings app is what makes ticket 19's app necessary.

Automatic keystone: the tilt sensor exists, but the component that sibling models use for it is not installed on this unit, so automatic correction is a stretch goal and manual is the target. Setting the properties works today partly because SELinux is switched off; if ticket 11 switches it on, the app must be a platform-signed system app or use a small root helper. Unresolved: projection orientation (ceiling, rear) was not found among the properties.
