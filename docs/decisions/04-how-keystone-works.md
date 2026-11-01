# 04 How keystone works

Type: research
Status: resolved

## Question

On H713 projectors of the HY300/HY320 family, where do keystone (manual and automatic) and projection orientation actually live: only in the stock launcher's screens, or in a system component another app can use? Does automatic keystone keep working without the stock launcher, and what must be confirmed on this unit's own backup?

## Answer

Keystone correction itself happens in Android's display system, not in the launcher. Automatic keystone runs in a separate vendor component (com.hysd.vafocus), so it should survive the launcher's removal; that component goes on the keep-list candidates. The stock launcher holds only the manual-keystone and orientation screens, so removing it means an own keystone app is needed. Everything rests on one reverse-engineered sister model (HY310) and must be confirmed on this unit's backup, including whether an ordinary app may set the corners.

Findings: [research/04-how-keystone-works.md](../research/04-how-keystone-works.md)
