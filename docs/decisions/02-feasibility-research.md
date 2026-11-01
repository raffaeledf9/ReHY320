# 02 Feasibility research

Type: research
Status: resolved

## Question

Is reworking the HY320 into a clean Android projector with AirPlay feasible, and which facts do the planning decisions rest on?

## Answer

Feasible for AirPlay (open-source AirPlay Server, with a 32-bit build), APK installs and a clean launcher. Genuine Google Cast is not possible on uncertified hardware. The malicious vendor apps sit on read-only partitions and come back after a factory reset, so they must be physically removed before the projector goes online. The router is end of life, with limited isolation and logging. Netflix runs only as the phone app, at about SD. The keystone screens likely live in the stock launcher.

Assets:
- [Feasibility report](../FEASIBILITY.md)
- [Verified feasibility data](../research/02a-feasibility-data.json)
- [Verified planning facts](../research/02b-planning-facts-data.json)
