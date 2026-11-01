#!/bin/sh
#
# Builds the Magisk module that hides the stock Android components this
# projector never uses but which hold the INTERNET permission. Run from the PC
# with the projector attached and rooted; it writes nothing to any partition,
# and deleting the module brings every one of them back.
#
#     sh scripts/clean/less-surface.sh
#
# Seven are hidden by masking their directory, which is Magisk's `.replace`.
# The eighth, Passpoint sign-up, is inside an APEX that a module cannot mount
# over, so service.sh disables it at each boot instead.

set -e
M=/data/adb/modules/hy320_less_surface
APP="WebScreensaver PrintRecommendationService PacProcessor"
PRIV="BuiltInPrintService ManagedProvisioning StatementService ProxyHandler"

run() { adb shell "su -c '$1'"; }

for d in $APP; do run "mkdir -p $M/system/app/$d && touch $M/system/app/$d/.replace"; done
for d in $PRIV; do run "mkdir -p $M/system/priv-app/$d && touch $M/system/priv-app/$d/.replace"; done

adb push scripts/clean/less-surface-service.sh /data/local/tmp/service.sh
run "cp /data/local/tmp/service.sh $M/service.sh && chmod 755 $M/service.sh"

run "cat > $M/module.prop <<'PROP'
id=hy320_less_surface
name=HY320: unused network-capable components removed
version=v1
versionCode=1
author=owner
description=Hides seven stock Android components that hold the INTERNET permission and that this projector never uses: the web screen saver, the built-in print service and its plugin recommender, managed provisioning, App Links verification, and the PAC proxy pair. Passpoint sign-up is inside an APEX and is disabled by service.sh at each boot instead. Nothing in any partition is changed.
PROP"

echo "built; reboot the projector to apply"
