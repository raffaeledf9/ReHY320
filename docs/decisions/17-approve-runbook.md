# 17 Approve the runbook

Type: grilling
Status: resolved
Blocked by: 05, 08, 10, 12, 13, 14, 15, 16, 19, 20, 21, 22, 23, 24, 25

## Question

Does the user approve the runbook assembled from every resolved ticket, step by step, with each device write and its undo?

## Draft ready for approval (2026-10-22)

Drafted at the runbook (the author's execution diary, not published): nine steps from here to the deployed projector, each with what it changes and how to undo it, plus what the project deliberately does not fix.

Everything the first steps need is built and verified on the PC. What the runbook still cannot promise, and says so:
- whether the cleaned container boots (the undo is proven, so a failure costs time, not the projector);
- whether an ordinary app may set the keystone properties;
- which projection value is which orientation;
- whether the Play Store works on this uncertified device.

Awaiting the user's approval, which is this ticket's resolution.

## Answer — approved (user, 2026-10-22)

The user approved the runbook (the author's execution diary, not published) after one addition they asked for: whether a newer Android could be installed. That was investigated and rejected on the evidence (32-bit only, so a generic image caps at Android 12, and such an image replaces the system partition where keystone, the focus motor, the remote's service and the HDMI input all live). The runbook now records that, and adds keeping the browser engine current as the thing that actually reduces exposure.

**This is the map's destination, so the map is complete.** What remains is execution of the runbook, which needs the user and the projector.
