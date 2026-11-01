# keys/

Empty on purpose.

`scripts/verity/` generates the AVB key pair here, and `app/build.ps1`
generates the app signing keystore in `app/`. Both stay on your machine and
both are in `.gitignore`.

`avbtool` also belongs here — it is AOSP's, not this project's. See
[../docs/EXTERNAL.md](../docs/EXTERNAL.md) for where to get it.

If you lose the app keystore, the next build cannot update the installed app
and you have to uninstall it first. If you lose the AVB key, you have to
re-sign every vbmeta partition again from scratch.
