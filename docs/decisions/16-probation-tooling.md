# 16 Probation tooling

Type: research
Status: resolved
Blocked by: 06

## Question

Given the router facts, how does the PC collect the router's connection log safely, match each address to its owner, and decide pass or fail? What is the list of expected destinations, and how does the 24-hour re-check reuse the same tools?

## Answer

With the router firewall on and connection logging set for probation, the stock ASUS sends the PC one plain-text syslog line per new outgoing connection (addresses and ports, no names). A small Python standard-library receiver on the PC collects it behind a narrow Windows firewall rule that accepts only the router. A fixed DHCP address for the projector makes its lines easy to filter. Each destination is explained by a name the router resolved, a confirmed reverse lookup or the address owner's registry record, and is compared with the normal Android baseline (connectivity check, time servers), the expected apps (AirPlay Server, Netflix and others) and the published malware lists. Probation passes after 7 days with every destination explained; the 24-hour re-check reuses the same tools. Updating the router to 382 changes none of this. To confirm on first run: whether the receiver needs admin rights for its port, and whether lease lines appear in the log. The receiver and analyzer code in the findings has not been run yet.

Findings: [research/16-probation-tooling.md](../research/16-probation-tooling.md)
