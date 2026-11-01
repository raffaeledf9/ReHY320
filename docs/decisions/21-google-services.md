# 21 Google Play Services: keep, and test the Play Store

Type: task
Status: resolved
Blocked by: 11, 23

## Question

Decided in ticket 10: Play Services and the service framework stay. Open: does the Play Store actually work on this uncertified device, once the vendor scripts that disabled Google's startup components are gone and those components are switched back on? HITL: test on the cleaned projector, then remove the Play Store if it does not work.

## Resolved as far as the map goes (2026-10-22)

Decided in ticket 10: Play Services and the framework stay, the Play Store is kept and tested, and removed only if it does not work. The test is step 7 of the approved runbook, because it needs the cleaned projector online.
