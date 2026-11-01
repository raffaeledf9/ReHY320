# 25 Rebuild verification with our own key — findings

Researched 2026-10-22 against AOSP's own sources, read at the `android11-release`
branch (the branch this projector's Android 11 comes from). No device was touched
and `avbtool` was not run. Confidence is marked per claim: **[High]** = read
straight out of the source or documentation that owns the behaviour, **[Medium]** =
sound inference from it, **[Low]** = needs checking before it is relied on.

Sources used throughout:

- `avbtool` itself: <https://android.googlesource.com/platform/external/avb/+/refs/heads/android11-release/avbtool>
- AVB README: <https://android.googlesource.com/platform/external/avb/+/refs/heads/android11-release/README.md>
- `libavb/avb_footer.h`, `libavb/avb_vbmeta_image.h`: same repository
- Android's userspace verity setup: <https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/fs_mgr/libfs_avb/fs_avb.cpp> and `.../libfs_avb/avb_util.cpp`
- init's first-stage mount: <https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/init/first_stage_mount.cpp> and `.../init/first_stage_init.cpp`
- fstab flag parsing: <https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/fs_mgr/fs_mgr_fstab.cpp>
- How AOSP's build sizes and footers a dynamic partition: <https://android.googlesource.com/platform/build/+/refs/heads/android11-release/tools/releasetools/verity_utils.py>
- Kernel dm-verity target: <https://docs.kernel.org/admin-guide/device-mapper/verity.html>
- Android's dm-verity page: <https://source.android.com/docs/security/features/verifiedboot/dm-verity>

---

## The short version

The plan works, and there is a better order to do it in than the ticket assumes.

Two results decide everything else:

1. **The root hash does not depend on the key.** A dm-verity root hash is a
   function of the filesystem bytes, the salt, the hash algorithm and the block
   size only — nothing in the hash tree involves a signature. So regenerating the
   tree over the **unmodified** filesystems with the recorded parameters must
   reproduce the manufacturer's own root hashes, byte for byte. That is a check
   we can run entirely on the PC, before any device write, and it either proves
   our parameters exactly right or tells us they are wrong. **[High]**

2. **Therefore the verification rebuild can be proven on the device before the
   cleaning**, as its own small, cheap step: build the three verification
   partitions over the untouched filesystems with our key, write only those
   (128 KB + 64 KB + 64 KB), and restart. The container is not touched, so if it
   boots, dm-verity has verified the real filesystems against *our* freshly signed
   root hashes and the whole mechanism is proven. The undo is three small writes.
   Only then clean the filesystems and repeat. **[Medium — follows from 1 plus
   how init consumes the data, below]**

And one thing the ticket does not mention, which is the real new risk:

3. **Android's init checks the verification data's digest against what the
   bootloader passes on the kernel command line, and that check is switched off
   today.** With the flags word at 3, `VERIFICATION_DISABLED` is set and init skips
   the check entirely. Set the flags back to 0 and the check becomes live again: if
   the bootloader's digest and the one init computes disagree, init calls
   `LOG(FATAL)` and the projector does not boot. It is *not* a signature check and
   our key is irrelevant to it — but it is a check that has not run on this unit
   since ticket 24, and it is the one most likely to bite. The original firmware
   shipped with flags 0 and booted, so bootloader and init did agree then; and
   ticket 24 proved the bootloader recomputes the digest from whatever we write.
   Both point to it passing. Step 2 above tests it for 256 KB of writes. **[High
   for the mechanism, Medium for it passing]**

---

## 1. Rebuilding each filesystem's verity data

### Footer or plain descriptor: this device has both

The distinction in the question is real:

- A **hashtree footer** is `AvbFooter`, a 64-byte struct whose magic is `AVBf`,
  always stored in the **last 64 bytes of the partition**; it records the original
  filesystem size and where to find the vbmeta struct that `add_hashtree_footer`
  also appended to the image.
  (`libavb/avb_footer.h`: `#define AVB_FOOTER_MAGIC "AVBf"`, `AVB_FOOTER_SIZE 64`,
  "This struct is always stored at the end of a partition.") **[High]**
- A **hashtree descriptor** is the record carrying the root hash, salt, offsets and
  sizes. It can live in the image's own appended vbmeta (reached via the footer)
  *and/or* be copied into a separate vbmeta partition. **[High]**

AOSP's standard build produces **both**: `verity_utils.py` runs
`avbtool add_hashtree_footer --partition_size <P> --partition_name <name> --image <img>`
(plus `--key`/`--algorithm`, `--salt` if set, and whatever the board puts in
`avb_add_hashtree_footer_args`) and never passes `--do_not_append_vbmeta_image`, so
the footer is written. The copy of that descriptor into `vbmeta_system.img` /
`vbmeta.img` happens elsewhere — in the build's `BOARD_AVB_*` rules, which call
`make_vbmeta_image --include_descriptors_from_image`, not in `verity_utils.py`.
The README spells out the chained case:
"the hash-tree descriptors for `system.img` and `system_ext.img` will be included
only in `vbmeta_system.img`, but not `vbmeta.img`" — the *descriptors*, not the
hashtree, which stays appended to the image. **[High]**

The recorded numbers say this unit was built exactly that way. I reproduced AOSP's
own sizing arithmetic (`calc_hash_level_offsets` and the Reed-Solomon size
`roots × ceil(blocks/(255−roots)) × 4096`) against the three partitions:

| | filesystem | tree (recorded) | tree (computed) | error correction (recorded) | computed |
|---|---|---|---|---|---|
| system | 1,028,796,416 | 8,110,080 | **8,110,080** | 8,200,192 | **8,200,192** |
| vendor | 113,328,128 | 901,120 | **901,120** | 909,312 | **909,312** |
| product | 318,095,360 | 2,510,848 | **2,510,848** | 2,539,520 | **2,539,520** |

All six match to the byte, with SHA-1 digests padded to 32 bytes (the next power of
two above 20 — `digest_padding = round_to_pow2(digest_size) - digest_size` in
avbtool), 4096-byte blocks, 2 error-correction roots, and the error correction
computed over **filesystem + tree together** (avbtool calls `generate_fec_data`
*after* appending the tree). That last point matters: the error-correction data
protects the hash tree as well as the data. **[High]**

The remaining slack to the end of each logical partition is 266,240 / 94,208 /
131,072 bytes — 65 / 23 / 32 blocks of 4096. That is precisely the shape a
footered build leaves: one block of vbmeta struct, a hole, and one final block
whose last 64 bytes are the footer. In all three cases the filesystem is exactly
4096 bytes below the maximum avbtool would allow for that partition size, so
passing the recorded partition size back to avbtool is accepted with one block to
spare. **[Medium]**

**Settle it from the golden backup, not from the device** — one read, no device
write:

```bash
# the last 64 bytes of each extracted logical partition
for p in system vendor product; do
  printf '%-8s ' "$p"; tail -c 64 "$p-original.img" | xxd | head -1
done
# a footer is present if the line starts: 41 56 42 66  ("AVBf")
```

If `AVBf` is there, reproduce it (the commands below do). If it is not, add
`--do_not_append_vbmeta_image` and zero-pad each image out to the recorded
partition size by hand, because nothing else will. Either way the hash tree and
the error-correction data are appended to the image regardless — in avbtool's
`add_hashtree_footer` the `image.append_raw(hash_tree_with_padding)` and the error
correction append are unconditional, and `--do_not_append_vbmeta_image` suppresses
only the vbmeta struct, the padding and the footer. **[High]**

### The commands

```bash
# system
avbtool add_hashtree_footer \
  --image          system.img \
  --partition_name system \
  --partition_size 1045372928 \
  --hash_algorithm sha1 \
  --block_size     4096 \
  --salt           2dce92049871165e758ccb37c810c3cc886ee0bd01fab5c122790c43cddd7b3a \
  --fec_num_roots  2 \
  --algorithm      SHA256_RSA2048 \
  --key            hy320_avb.pem \
  --rollback_index 0

# vendor  — same, with --partition_name vendor  --partition_size 115232768
# product — same, with --partition_name product --partition_size 323276800
```

`system.img` here is the **filesystem alone**, 1,028,796,416 bytes. One convenience
worth knowing: if you hand avbtool the whole extracted logical partition instead,
it finds the old footer, truncates back to `footer.original_image_size` and
regenerates from there — `add_hashtree_footer` is deliberately idempotent
("This way 'avbtool add_hashtree_footer' is idempotent (modulo salts)"). That makes
the rebuild safe to re-run. **[High]**

### Which switch controls what

| Parameter | Switch | Note |
|---|---|---|
| salt | `--salt HEX` | hex, used verbatim. The recorded 32-byte salt is not avbtool's default (which is 20 random bytes for SHA-1), so it must be passed explicitly — all three partitions share it. |
| hash algorithm | `--hash_algorithm sha1` | avbtool's default for `add_hashtree_footer` is already `sha1`; pass it anyway so the script does not depend on a default. |
| data + hash block size | `--block_size 4096` | one switch sets both; avbtool writes `data_block_size` and `hash_block_size` from it, which is why both read 4096. |
| error-correction roots | `--fec_num_roots 2` | default is also 2. |
| no error correction | `--do_not_generate_fec` | generated by default; `--generate_fec` is a deprecated no-op that only prints a warning. |
| partition name | `--partition_name system` | this is the name init looks the descriptor up by. Must match exactly, no A/B suffix. |
| partition size | `--partition_size N` | with a footer: avbtool pads the image out so the final size is **exactly** N. Without a footer it is only a sanity bound. |
| footer written or not | `--do_not_append_vbmeta_image` | suppresses vbmeta struct + padding + footer. The tree and error correction are appended either way. |
| descriptor to a separate file | `--output_vbmeta_image FILE` | writes the vbmeta struct (with the hashtree descriptor in it) to its own file. |
| signing | `--algorithm SHA256_RSA2048 --key key.pem` | `--algorithm NONE` is the default and leaves it unsigned. |
| dm-verity version | — | no switch: avbtool hardcodes `ht_desc.dm_verity_version = 1`, which is what this unit records. |

All of the above read from `add_hashtree_footer`'s argument definitions and body in
avbtool. **[High]**

---

## 2. The key

```bash
openssl genrsa -out hy320_avb.pem 2048
```

That is all avbtool needs. It never loads a key library: it shells out to
`openssl rsa -in <key> -modulus -noout` to read the modulus and to
`openssl rsautl -sign -inkey <key> -raw` to sign, so any unencrypted PEM private
key `openssl rsa` can read will do. **[High]**

Two hard requirements:

- **Exponent must be 65537.** avbtool refuses anything else: "Only RSA keys with
  exponent 65537 are supported." `openssl genrsa`'s default is 65537, so the plain
  command above is correct. **[High]**
  (<https://docs.openssl.org/1.1.1/man1/genrsa>: "The public exponent to use,
  either 65537 or 3. The default is 65537.")
- **2048 bits**, to match this unit. The chain descriptors hold a 520-byte key
  blob, and avbtool's `encode_rsa_key` emits 8 header bytes plus two numbers of
  `key_num_bits/8` each — 8 + 256 + 256 = 520. That arithmetic only works for a
  2048-bit key, which independently confirms the reading. **[High]**

Do not pass a passphrase: `openssl genrsa` leaves the key unencrypted unless a
cipher option is given, and avbtool's non-interactive `openssl` calls cannot
answer a prompt. **[High]** Protect it by where it lives, not by a passphrase —
the PC, off the projector, never on the device, and in the same place as the
golden backup's manifest so a later rebuild can be signed by the same key.

The public-key blob that goes into a chain descriptor:

```bash
avbtool extract_public_key --key hy320_avb.pem --output hy320_avb.avbpubkey
wc -c < hy320_avb.avbpubkey      # must print 520
```

This is avbtool's own format (`AvbRSAPublicKeyHeader` plus modulus and the
Montgomery constant), **not** a PEM public key, and it is what
`--chain_partition`'s third field expects. **[High]**

---

## 3. The three verification partitions

Mirror the original layout exactly: the descriptors for system and vendor go in
their own chained partitions, product's stays in the top-level one, and the
top-level one points at the other two.

```bash
# vbmeta_system (64 KB) — carries system's hashtree descriptor
avbtool make_vbmeta_image \
  --output vbmeta_system.img \
  --include_descriptors_from_image system.img \
  --algorithm SHA256_RSA2048 --key hy320_avb.pem \
  --rollback_index 0 --flags 0 \
  --padding_size 65536

# vbmeta_vendor (64 KB) — carries vendor's
avbtool make_vbmeta_image \
  --output vbmeta_vendor.img \
  --include_descriptors_from_image vendor.img \
  --algorithm SHA256_RSA2048 --key hy320_avb.pem \
  --rollback_index 0 --flags 0 \
  --padding_size 65536

# vbmeta (128 KB) — boot/dtbo/vendor_boot hashes, product's hashtree,
#                   the properties, and the two chains
avbtool make_vbmeta_image \
  --output vbmeta.img \
  --include_descriptors_from_image boot.img \
  --include_descriptors_from_image dtbo.img \
  --include_descriptors_from_image vendor_boot.img \
  --include_descriptors_from_image product.img \
  --chain_partition vbmeta_system:1:hy320_avb.avbpubkey \
  --chain_partition vbmeta_vendor:2:hy320_avb.avbpubkey \
  --prop  <each property read off the original, see below> \
  --algorithm SHA256_RSA2048 --key hy320_avb.pem \
  --rollback_index 0 --flags 0 \
  --padding_size 131072
```

Notes on each part:

- **`--include_descriptors_from_image` copies descriptors, it does not recompute
  them.** avbtool parses the given image (footer first, else a bare vbmeta at
  offset 0) and copies the descriptors it finds. So for `boot.img`, `dtbo.img` and
  `vendor_boot.img` — which we are not changing — this carries the manufacturer's
  own hash descriptors across verbatim, digests included, with no need to
  recompute or even understand them. Property descriptors ride along the same way.
  **[High]**
- **Do not point `--include_descriptors_from_image` at the original
  `vbmeta.img`.** It would copy the manufacturer's *chain* descriptors too, with
  the manufacturer's public key in them, and the chained partitions would then be
  expected to be signed by a key we do not have. Include from the individual
  partition images only. **[High]**
- If it turns out `boot.img` / `dtbo.img` / `vendor_boot.img` carry no footer, the
  fallback is to rebuild their hash descriptors with `avbtool add_hash_footer` on
  *copies*, using the algorithm and salt read out of the original vbmeta — a hash
  descriptor's digest is just the hash of salt followed by the image, so it
  reproduces exactly — and then include from those copies. **[Medium]**
- **Chain descriptors**: the format is
  `--chain_partition PART_NAME:ROLLBACK_SLOT:KEY_PATH`. Rollback index *locations*
  1 and 2 match what AOSP's build generates for these two partitions
  (`BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1`, with vbmeta_vendor
  taking 2), and the recorded values confirm it. avbtool rejects a location below 1
  and rejects two chains sharing a location. **[High]**
- **One key for all three.** libavb compares the public key embedded in a chained
  vbmeta against the key in the chain descriptor that pointed at it, and reports
  `ERROR_PUBLIC_KEY_REJECTED` if they differ. Using `hy320_avb.pem` to sign
  vbmeta, vbmeta_system and vbmeta_vendor, and `hy320_avb.avbpubkey` in both chain
  descriptors, satisfies that by construction. **[High]**
- **Fixed partition sizes** are met with `--padding_size`, which pads to a
  multiple of the given number: a blob of a few KB padded to a multiple of 65536
  comes out at exactly 65536, and to a multiple of 131072 at exactly 131072. This
  is cosmetic for verification — init reads the struct's declared block sizes and
  sets the vbmeta's length from them, so trailing padding is neither read nor
  digested — but it means one `fastboot flash` overwrites the whole partition
  instead of leaving a tail of the old contents behind. Worth doing. **[High]**
  If a blob ever exceeds 65536 the padding silently becomes 131072 and will not
  fit the partition, so the script must assert the output size.
- **`--flags 0`** is the default and is the point of the exercise: it clears both
  `HASHTREE_DISABLED` (bit 0) and `VERIFICATION_DISABLED` (bit 1), the two bits
  ticket 24 set to 3. The flags word sits at offset 120 of the vbmeta header, big
  endian — which is exactly the single byte at offset 123 that ticket 24 changed.
  **[High]**
- **`--rollback_index`**: nothing on this device enforces it (see §4), but read the
  original values with `info_image` and reproduce them rather than assuming 0.
- **Descriptor order** inside the blob will differ from the original: avbtool emits
  chain descriptors first, then properties, then descriptors copied from images
  sorted by type and partition name. Order is irrelevant — libavb walks the list
  and matches by partition name. **[High]**
- **Properties**: the ones attached to a partition come across automatically with
  that partition's descriptors. Any property belonging to the top-level vbmeta
  itself must be re-added by hand with `--prop KEY:VALUE`. The only one Android 11
  actually reads is `com.android.build.<partition>.security_patch`, via
  `AvbHandle::GetSecurityPatchLevel`, and that is used only on the `avb_keys`
  code path for detecting a rolled-back standalone image — not on this device's
  path. So carrying them over is for honesty and for anything that reads build
  metadata, not for booting. Carry them all; they cost nothing. **[High]**

---

## 4. What Android 11's init actually requires

The chain is: the bootloader runs its own AVB check, then passes the result on the
kernel command line; init's first-stage mount reads the real verification
partitions itself and sets up dm-verity from the descriptors.

**Does the signature have to validate against anything?** In userspace, **no** for
the top-level partition. `fs_avb` says so in its own comment: the operations handed
to libavb are *dummy* ones, so "`avb_ops->validate_vbmeta_public_key()` used to
validate the public key of the top-level vbmeta always pass in userspace here".
Nothing on the device holds a copy of a trusted key to compare ours against.
libavb does still check that each vbmeta's signature is internally consistent with
the public key embedded in it, and that a chained vbmeta's embedded key matches the
chain descriptor that pointed at it — both of which hold by construction when we
sign everything with one key. **[High]**

**What does have to match: the digest.** Unless `VERIFICATION_DISABLED` is set,
`AvbHandle::Open()` builds an `AvbVerifier` from `androidboot.vbmeta.size`,
`androidboot.vbmeta.hash_alg` and `androidboot.vbmeta.digest` on the kernel command
line, hashes the concatenation of every vbmeta struct it loaded, and compares both
the total size and the digest. A mismatch logs `VerifyVbmetaImages failed` and
returns nothing, and that propagates: `InitAvbHandle()` fails, `SetUpDmVerity()`
fails, `DoFirstStageMount()` fails, and `first_stage_init.cpp` ends at
`LOG(FATAL) << "Failed to mount required partitions early ..."`. **[High]** This is
the check described in point 3 of the summary — it is not about our key, it is
about the bootloader and init agreeing on what is in the vbmeta partitions.

**Does it read only the hashtree descriptors?** For setting up dm-verity, yes.
`LoadAvbHashtreeToEnableVerity` derives the partition name from the fstab entry and
calls `GetHashtreeDescriptor`, which walks **every** vbmeta image that was loaded
and takes the first hashtree descriptor whose partition name matches. It then
builds the dm-verity table straight out of the descriptor fields — version,
block sizes, `image_size/data_block_size` as the data block count,
`tree_offset/hash_block_size` as the tree's start, the algorithm, the root digest
and the salt — and adds the error-correction parameters only
`if (hashtree_desc.fec_size > 0)`. **[High]**

**What the fstab's `avb` flag means.** In `fs_mgr_fstab.cpp` bare `avb` is matched by
the exact-match flag table (`CheckFlag("avb", avb)`), which sets the boolean and
stops there; `avb=<name>` does not match exactly, so it falls through to
`StartsWith(flag, "avb")`, which sets the same boolean **and** `vbmeta_partition` to
`<name>`. (`avb_keys=` is tested before both — comment: "must before the following
avb" — and sets only `avb_keys`, not the boolean.) That value does **not** select which vbmeta the
descriptor is read from — it is collected into `vbmeta_partitions_` by
`FirstStageMountVBootV2` so that init creates the block device for it before
verification runs, since "Any partitions needed for verifying the partitions used
in first stage mount, e.g. vbmeta must be provided as vbmeta_partitions". What
actually causes `vbmeta_system` and `vbmeta_vendor` to be loaded is the **chain
descriptors in the top-level vbmeta**, which libavb follows. So both pieces are
needed, and the chain structure must be reproduced faithfully — which §3 does.
A separate flag, `avb_keys=`, selects a different path that *does* match the
signing key against key files on disk; that path is for DSU and standalone images,
and if this unit's fstab uses it the plan changes, so read the fstab. **[High]**

**What the user sees if a root hash is wrong.** The dm-verity table loads fine —
the failure happens on the first read of a bad block, which is immediate, because
init mounts the filesystem straight away. The behaviour then comes from
`androidboot.veritymode`, which `ConstructVerityTable` translates:
`enforcing` → `restart_on_corruption`, `eio` → the kernel default EIO,
`logging` → `ignore_corruption`; **and when the parameter is absent it defaults to
`enforcing`**. The kernel documentation for `restart_on_corruption` is blunt:
"Restart the system when a corrupted block is discovered." So the realistic failure
is **a reboot loop** — the projector restarts, gets as far as mounting, and
restarts again, most likely showing the vendor logo over and over with no Android.
**[High]**

Two other shapes of failure, for completeness:

- Wrong digest on the command line, or a vbmeta init cannot parse: init panics at
  first-stage mount. The projector reboots or sits dead before any UI. **[High]**
- A tree that is the right shape but describes the wrong offsets: dm-verity reads
  nonsense as hashes and corruption is reported on the first block. Same reboot
  loop. **[Medium]**

In every case the undo is the same and small: hold the power button at start-up to
reach fastboot with no Android (ticket 23), and write the three verification
partitions back from the golden backup — 256 KB in total, far less than the
six-minute container write.

**What does *not* protect us:** rollback indexes. In userspace the dummy
`read_rollback_index()` always returns zero, so the rollback check cannot fail
there; and this unit's bootloader does not check signatures either, so it is very
unlikely to be enforcing stored rollback indexes. Treat rollback protection as
absent. **[High for userspace, Medium for the bootloader]**

---

## 5. Is the error-correction data optional?

Yes, at every level.

- At build time: `--do_not_generate_fec` omits it, and the descriptor's `fec_size`
  stays 0. **[High]**
- At mount time: `ConstructVerityTable` adds the error-correction parameters only
  when `fec_size > 0`, so a descriptor without it simply produces a dm-verity
  table without it. **[High]**
- In the kernel: "FEC is optional and is enabled only through
  `use_fec_from_device`." **[High]**

What is lost without it: the ability to *repair* damage instead of merely detecting
it. The kernel's Reed-Solomon code with the recorded 2 roots is RS(255, 253), about
0.8% space overhead, with codewords interleaved across the whole device so that a
long run of bad or unreadable blocks can still be recovered; it runs only when a
block fails its hash check or cannot be read, and a corrected block is re-checked
against its expected hash before use, so it never weakens the integrity check.
**[High]**

For this projector that is worth keeping. The failure mode it covers is exactly the
one this rebuild is for — storage decay on a cheap eMMC — and without it a single
decayed block in the system filesystem turns into a reboot loop instead of a
silently repaired read. It also costs nothing in space: the recorded partition
sizes already budget for it, and dropping it would leave the images shorter than
the logical partitions and force hand-padding anyway.

The practical catch is in §"Tooling" below: avbtool does not compute it itself, it
shells out to a separate `fec` binary.

---

## 6. Regenerating everything after a later change, and checking it before writing

### The script

One script, run on the PC, which rebuilds everything from the extracted
filesystems. Nothing in it is specific to *which* change was made, so it serves
every later change equally.

```bash
#!/bin/bash
# rebuild-verification.sh  —  regenerate verity data + the three vbmeta
# partitions for the HY320 after changing any of the three filesystems.
# Takes a staging directory holding system.img, vendor.img, product.img
# (filesystems only) plus boot.img, dtbo.img, vendor_boot.img from the
# golden backup. Writes nothing to the projector.
set -euo pipefail

STAGE=${1:?staging directory}
KEY=${2:?private key pem}
PUB=${STAGE}/hy320_avb.avbpubkey
SALT=2dce92049871165e758ccb37c810c3cc886ee0bd01fab5c122790c43cddd7b3a
ALG=SHA256_RSA2048

avbtool extract_public_key --key "$KEY" --output "$PUB"
[ "$(wc -c < "$PUB")" = 520 ] || { echo "public key blob not 520 bytes"; exit 1; }

# --- per-filesystem: tree, error correction, footer -------------------------
# name            partition size   (expected filesystem size)
set -- "system 1045372928 1028796416" \
       "vendor  115232768  113328128" \
       "product 323276800  318095360"
for spec in "$@"; do
  set -- $spec; name=$1; psize=$2; fssize=$3
  [ "$(stat -c%s "$STAGE/$name.img")" = "$fssize" ] \
    || { echo "$name: filesystem is not $fssize bytes — layout would change"; exit 1; }
  avbtool add_hashtree_footer \
    --image "$STAGE/$name.img" --partition_name "$name" \
    --partition_size "$psize" \
    --hash_algorithm sha1 --block_size 4096 --salt "$SALT" \
    --fec_num_roots 2 \
    --algorithm "$ALG" --key "$KEY" --rollback_index 0
  [ "$(stat -c%s "$STAGE/$name.img")" = "$psize" ] \
    || { echo "$name: image is not exactly $psize bytes"; exit 1; }
done

# --- the three verification partitions --------------------------------------
avbtool make_vbmeta_image --output "$STAGE/vbmeta_system.img" \
  --include_descriptors_from_image "$STAGE/system.img" \
  --algorithm "$ALG" --key "$KEY" --rollback_index 0 --flags 0 \
  --padding_size 65536
avbtool make_vbmeta_image --output "$STAGE/vbmeta_vendor.img" \
  --include_descriptors_from_image "$STAGE/vendor.img" \
  --algorithm "$ALG" --key "$KEY" --rollback_index 0 --flags 0 \
  --padding_size 65536
avbtool make_vbmeta_image --output "$STAGE/vbmeta.img" \
  --include_descriptors_from_image "$STAGE/boot.img" \
  --include_descriptors_from_image "$STAGE/dtbo.img" \
  --include_descriptors_from_image "$STAGE/vendor_boot.img" \
  --include_descriptors_from_image "$STAGE/product.img" \
  --chain_partition "vbmeta_system:1:$PUB" \
  --chain_partition "vbmeta_vendor:2:$PUB" \
  --algorithm "$ALG" --key "$KEY" --rollback_index 0 --flags 0 \
  --padding_size 131072
  # plus one --prop KEY:VALUE per property read off the original vbmeta

for p in "vbmeta.img 131072" "vbmeta_system.img 65536" "vbmeta_vendor.img 65536"; do
  set -- $p
  [ "$(stat -c%s "$STAGE/$1")" = "$2" ] || { echo "$1: wrong size"; exit 1; }
done

# --- check before anything is written ---------------------------------------
avbtool verify_image --image "$STAGE/vbmeta.img" --key "$KEY" \
  --expected_chain_partition "vbmeta_system:1:$PUB" \
  --expected_chain_partition "vbmeta_vendor:2:$PUB" \
  --follow_chain_partitions
avbtool calculate_vbmeta_digest --hash_algorithm sha256 \
  --image "$STAGE/vbmeta.img" | tee "$STAGE/expected-vbmeta-digest.txt"
```

### What the checks actually prove

- **`verify_image`** checks the signature of each vbmeta against its own embedded
  key, checks that the embedded key is ours (`--key`), checks each chain descriptor
  against the rollback location and key we expect, follows the chains, and — for
  every hashtree descriptor — **regenerates the whole tree from the image and
  compares both the root digest and the on-disk tree bytes**. The regeneration is
  delegated to `AvbHashtreeDescriptor.verify`, which calls `generate_hash_tree` and
  then tests `root_digest != self.root_digest` and `hash_tree != hash_tree_ondisk`;
  its success line is
  `'{}: Successfully verified {} hashtree of {} for image of {} bytes'`, so look for
  `system: Successfully verified sha1 hashtree of …/system.img for image of
  1028796416 bytes`. It opens each image as
  `os.path.join(image_dir, partition_name + image_ext)`, where both the directory
  and the extension come from the vbmeta file you passed — so with
  `--image vbmeta.img` it needs `system.img` next to it. Hence the staging
  directory. **[High]**
  One gap to know about: it does **not** verify the error-correction data. avbtool
  says so in a comment — doing it "currently requires the 'fec' binary … and takes
  a long time … and is not strictly needed … as we've already verified the root
  hash." **[High]**
- **`calculate_vbmeta_digest`** gives the digest the bootloader should report after
  the write. Ticket 24 already showed this unit puts that value on the kernel
  command line, so after rebooting, comparing `androidboot.vbmeta.digest` against
  this file confirms the bootloader read exactly what we wrote. **[Medium]**
  It follows the chain descriptors itself — hashing the top-level blob first, then
  each chained blob in descriptor order, which is the same order init hashes them
  in — and it finds the chained blobs as `<partition_name><ext>` beside the image
  given, so `vbmeta_system.img` and `vbmeta_vendor.img` must sit next to
  `vbmeta.img`. The script's staging directory satisfies that. **[High]**
- **The root-hash equality check — the one worth running first.** Run the script
  over **unmodified** filesystems extracted from the golden backup and compare each
  root digest (`avbtool info_image --image system.img`) against the value in the
  original vbmeta. They must be identical, because a root hash depends only on the
  filesystem bytes, the salt, the algorithm and the block size. If all three match,
  every parameter in §1 is proven correct with no device write at all. If one does
  not, stop: something about the reading is wrong, and no amount of signing will
  fix it. **[High]**

### The order on the device

1. Run the script over unmodified filesystems; confirm the three root digests equal
   the manufacturer's. Pure PC, no device write.
2. **Device write:** flash only `vbmeta.img`, `vbmeta_system.img`,
   `vbmeta_vendor.img` from step 1 — 256 KB — leaving the container untouched.
   Restart. If Android comes up, dm-verity has verified the real filesystems
   against our own freshly signed root hashes, the digest check has passed, and the
   chain structure is right. This is the proof the ticket asks for, obtained before
   anything irreversible. Undo: the three originals from the golden backup.
3. Confirm from the device that verification is really on this time: the three
   partitions should now mount as *verity* mappings of the smaller signed area
   (system 2,009,368 sectors, per ticket 24's own arithmetic) rather than the
   full-size plain mappings seen with the flags set, and the kernel log should show
   verity being set up.
4. Then clean the filesystems, rerun the script, write the container, and write the
   three verification partitions again.

Step 2 is the whole reason to do this in two passes: it separates "our verity
machinery is correct" from "our cleaning is correct", so a projector that will not
boot has only one possible cause. Same principle as ticket 20's decision to leave
the mandatory-access-control layer for its own step.

---

## 7. The honest limits

The bootloader does not check the verification partition's signature — that is
proven, it is why ticket 24 worked. So what this buys:

**It does protect against:**

- **Storage decay.** Every block of system, vendor and product is checked on read
  (except blocks whose expected content is all zeros: Android always passes
  `ignore_zero_blocks`, unconditionally, in `ConstructVerityTable`),
  and with the error-correction data a damaged block is repaired rather than
  merely detected. This is the realistic threat for a cheap projector left powered
  for years, and it is the main reason to do this at all.
- **Change by anything that is not already root.** A compromised app, or anything
  arriving over the network, cannot alter the three protected filesystems without
  the change being detected on the next read. Combined with decision 3 of ticket 20
  — the raw storage device dropping from 0666 to `0440 root shell` — the vendor's
  "any app can write the whole eMMC" hole closes and the integrity check covers
  what is left.
- **Our own mistakes.** Any later change that forgets to regenerate the trees
  announces itself immediately and loudly, rather than leaving a system that is
  subtly wrong.
- **Silent substitution.** Nobody can swap a filesystem for a modified one without
  also replacing the matching verification partition.

**It does not protect against:**

- **An attacker who is already root on the device.** They can regenerate the trees
  and the verification partitions exactly as our script does, and nothing in the
  boot chain would object. There is no hardware root of trust in play.
- **Anyone with physical access and a USB cable.** fastboot writes whatever it is
  given; setting the flags back to 3 is one 128 KB write, which is precisely how we
  got here.
- **Rollback.** Rollback indexes are not enforced — zero in userspace, and almost
  certainly unchecked by this bootloader — so an older signed set can be put back.
- **The boot chain itself.** boot, vendor_boot and dtbo are covered by plain
  hashes whose descriptors we carry over, but nothing verifies the bootloader, and
  the kernel command line that keeps the mandatory-access-control layer in logging
  mode lives in vendor_boot. Verification does not change ticket 20's decision 1.

So the accurate description for the runbook is: **integrity checking with a key we
control, not verified boot.** It makes the projector self-checking and it makes
unauthorised change detectable; it does not make the projector resistant to
someone who already has root or a cable. That is a real improvement over both the
stock state and the relaxed state, and it should be written down as exactly that
much and no more. Signing with our own key is what makes the *rebuild* possible —
init needs a signature that is internally consistent — rather than being what
provides the security.

One consequence to record next to ticket 11's note: once this is in place,
**every** later change to system, vendor or product must rerun the script and
rewrite the three verification partitions. Forgetting means a reboot loop, with the
undo in hand. The private key becomes a permanent dependency of the projector:
lose it and the only route back is the relaxed 128 KB verification partition again.

---

## Tooling needed on the PC

Three things, all worth settling before the runbook is written, because two of them
can stop the script dead.

1. **`avbtool` from `android11-release`.** It is one file and it reports itself as
   `avbtool 1.1.0`, matching what this unit's partitions record — so the rebuilt
   data will carry the same release string. It is **Python 2 only**: it uses
   `2L**32` and Python-2 string/bytes mixing, and its build definition enables the
   `py2` variant. Ubuntu 20.04 still has `python2` in its archive, which is the
   straightforward route. The alternative — a newer avbtool (1.2.0+, Python 3) —
   works functionally but stamps `avbtool 1.2.0` into the vbmeta and adds switches
   that do not exist in 1.1.0, so the written procedure should pin 1.1.0. **[High]**
   Note that `--rollback_index_location` does **not** exist in 1.1.0; the rollback
   location is the middle field of `--chain_partition`.
2. **`openssl`.** Ubuntu 20.04's 1.1.1 is fine. Worth knowing for any later move to
   a newer distribution: avbtool signs via `openssl rsautl`, which OpenSSL 3.x
   deprecates and may eventually remove. **[Medium]**
3. **The `fec` host binary, on `PATH`.** avbtool does not compute the
   error-correction data itself — it runs `fec --encode --roots 2 <image> <tmpfile>`
   and `fec --print-fec-size <size> --roots 2`, and `external/avb`'s build definition declares
   `required: ["fec"]`. Without it on `PATH`, `add_hashtree_footer` fails with
   `FileNotFoundError: 'fec'`. It is a `cc_binary_host` defined at
   `system/extras/verity/fec/Android.bp`
   (<https://android.googlesource.com/platform/system/extras/+/refs/heads/android11-release/verity/fec/Android.bp>),
   so getting it means building it from AOSP source. **[High]** This is the one
   real tooling obstacle, and it is the only reason §5's "drop the error
   correction" is tempting. My advice is to build it: the error correction is the
   part of this that earns its keep on a cheap eMMC.

---

## Still to read off the golden backup (no device write needed)

Each of these is a read of bytes we already hold, and each one firms up a
**[Medium]** above into a **[High]**:

1. **Footer or no footer**: the last 64 bytes of each extracted logical partition —
   `AVBf` present or not (command in §1). Decides whether `--partition_size` alone
   reproduces the layout or `--do_not_append_vbmeta_image` plus hand-padding is
   needed.
2. **The signing algorithm**: `algorithm_type` at offset 28 of each vbmeta header,
   or just `avbtool info_image --image vbmeta-original.img`. `SHA256_RSA2048` is
   AOSP's documented pairing for a 2048-bit chained vbmeta and almost certainly
   right, but it costs one read to know.
3. **The exact property descriptors and rollback index values** in all three
   original vbmeta partitions, so §3's `--prop` and `--rollback_index` reproduce
   them instead of guessing.
4. **Whether `boot.img`, `dtbo.img` and `vendor_boot.img` carry footers**, which
   decides whether `--include_descriptors_from_image` works on them directly or
   the fallback in §3 is needed.
5. **The fstab entries** for `/system`, `/vendor` and `/product` — from the
   vendor_boot ramdisk or `/vendor/etc/fstab.*` — specifically whether they use
   bare `avb`, `avb=<name>`, or `avb_keys=`. The first two are the path analysed in
   §4; `avb_keys=` would mean the signing key *is* matched against key files inside
   the filesystems, which would change §3.
6. **`androidboot.veritymode` on this unit's kernel command line** — in the dump
   ticket 24 already took, or one `cat /proc/cmdline`. This decides what a wrong
   root hash actually looks like: absent or `enforcing` gives the reboot loop §4
   predicts, `eio` gives a device that boots and throws read errors instead, and
   `logging` would ignore corruption altogether. The bootloader that already emits
   `androidboot.vbmeta.digest` almost certainly emits this too, so the prediction in
   §4 should be checked against it rather than against the default.

---

## Verification

Independent check, 2026-10-22: every claim below was re-read in the source that owns
it, trying to refute it. Verdicts: **confirmed** (quoted from the source),
**partly** (true in substance, detail off — fixed in place), **refuted**, or
**unverified** (not readable this pass).

**Note on sources.** AOSP's own gitiles view of `avbtool` truncates at about 121 KB
of rendered text, which is short of the argparse block and the `verify` bodies.
Those were read from the LineageOS android-11 mirror of `external/avb`
(<https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-18.1/avbtool>).
Everything that *was* visible on AOSP — the footer class, `MAX_VBMETA_SIZE`,
`MAX_FOOTER_SIZE`, the `openssl` calls, the exponent error, the `max_image_size`
formula, `2L**32` — matches the mirror word for word, and both report
`avbtool 1.1.0`, so the mirror is being treated as faithful for this file. Worth
one `diff` against a real AOSP checkout before the script is written.

### §1 Sizes and parameters

- **Tree sizes 8,110,080 / 901,120 / 2,510,848 and error-correction sizes
  8,200,192 / 909,312 / 2,539,520 — confirmed, and independently.** I re-implemented
  `calc_hash_level_offsets` (round each level's `blocks × 32` up to 4096, feed the
  result back until it fits one block) and the FEC formula
  `roots × ceil(blocks/253) × 4096`, and all six numbers and both offsets come out
  exactly as recorded, with the error correction computed over filesystem **plus**
  tree. Level sizes, for the record: system 8,040,448 + 65,536 + 4,096; vendor
  888,832 + 8,192 + 4,096; product 2,486,272 + 20,480 + 4,096. This is the strongest
  single result in the document: six independent numbers matching to the byte is not
  a coincidence, so the recorded parameters are right.
  (<https://android.googlesource.com/platform/external/avb/+/refs/heads/android11-release/avbtool>,
  <https://docs.kernel.org/admin-guide/device-mapper/verity.html>)
- **"The filesystem is exactly 4096 bytes below the maximum avbtool would allow"
  — confirmed.** avbtool's own formula is
  `max_metadata_size = max_fec_size + max_tree_size + self.MAX_VBMETA_SIZE + self.MAX_FOOTER_SIZE`
  then `max_image_size = partition_size - max_metadata_size`, with
  `MAX_VBMETA_SIZE = 64 * 1024` and `MAX_FOOTER_SIZE = 4096`. Computed for the three
  recorded partition sizes it gives 1,028,800,512 / 113,332,224 / 318,099,456 —
  exactly one 4096-byte block above each recorded filesystem. So all three were
  built by `add_hashtree_footer --partition_size <the recorded size>`, and re-running
  it with the same numbers is accepted with one block to spare. (same URL)
- **SHA-1 digests padded to 32 bytes — confirmed.**
  `digest_padding = round_to_pow2(digest_size) - digest_size`, and the arithmetic
  above only closes with 32. (same URL)
- **Footer struct: `AVBf`, 64 bytes, last 64 bytes of the partition — confirmed.**
  `class AvbFooter: MAGIC = 'AVBf'; SIZE = 64`, docstring "Footers are stored at the
  end of partitions and point to where the AvbVBMeta blob is located." (same URL)
- **"This device uses both a footer and separate descriptors" — confirmed as the
  AOSP pattern, still inferred for this unit.** `verity_utils.py` passes
  `--partition_size`, `--partition_name`, `--image` (plus key/algorithm/salt and the
  board's extra args) and never `--do_not_append_vbmeta_image`, so stock builds get
  a footer; the README states "the hash-tree descriptors for `system.img` and
  `system_ext.img` will be included only in `vbmeta_system.img`". The `AVBf` read in
  §1 is still the thing that settles it for this unit.
  (<https://android.googlesource.com/platform/build/+/refs/heads/android11-release/tools/releasetools/verity_utils.py>,
  <https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-18.1/README.md>)
  *Fixed in place:* the document credited the descriptor-copying step to
  `verity_utils.py`; that file only adds the footer and never calls
  `make_vbmeta_image`. The copy is done by the build's `BOARD_AVB_*` rules.
- **Tree and error correction are appended regardless of
  `--do_not_append_vbmeta_image` — confirmed.** The append order in
  `add_hashtree_footer` is: block-size rounding, `hash_tree_with_padding`,
  `fec_data_with_padding` (if FEC), and only then, under
  `if not do_not_append_vbmeta_image:`, the vbmeta blob, an `append_dont_care` hole
  of `partition_size - image_size - 1*block_size`, and the footer block. That hole
  is also what produces the "one block of vbmeta, a hole, one footer block" shape
  the document reads off the 65/23/32 blocks of slack. (avbtool, same URL)
- **Idempotency — confirmed.** "If there's already a footer, truncate the image to
  its original size. This way 'avbtool add_hashtree_footer' is idempotent (modulo
  salts)." (same URL)

### §1 Switch table — every row confirmed verbatim from argparse

`--hash_algorithm` "(default: sha1)"; `--salt` "Salt in hex (default: /dev/urandom)";
`--block_size` "(default: 4096)" and the body sets both
`ht_desc.data_block_size = block_size` and `ht_desc.hash_block_size = block_size`;
`--fec_num_roots` "(default: 2)"; `--do_not_generate_fec` "Do not generate
forward-error-correction codes"; `--generate_fec` with `help=argparse.SUPPRESS` and a
stderr warning "The --generate_fec option is deprecated since FEC is now generated by
default"; `--partition_name` "" default; `--partition_size` default 0;
`--do_not_append_vbmeta_image` "Do not append vbmeta struct or footer to the image";
`--output_vbmeta_image` "Also write vbmeta struct to file"; `--algorithm` "(default:
NONE)"; `--rollback_index` default 0; `ht_desc.dm_verity_version = 1` hardcoded with
no switch. **Confirmed.** Also confirmed: **no `--rollback_index_location` exists in
this version** — the location is the middle field of `--chain_partition`, whose
metavar is literally `PART_NAME:ROLLBACK_SLOT:KEY_PATH`.
(<https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-18.1/avbtool>)

### §2 The key

- **Exponent must be 65537 — confirmed.** `encode_rsa_key` raises
  `AvbError('Only RSA keys with exponent 65537 are supported.')`. (same URL)
- **avbtool shells out to openssl, so any unencrypted PEM works — confirmed.**
  `['openssl', 'rsa', '-in', key_path, '-modulus', '-noout']` to read the modulus,
  `['openssl', 'rsautl', '-sign', '-inkey', key_path, '-raw']` to sign. A passphrase
  would stall both. (same URL)
- **520-byte blob proves a 2048-bit key — confirmed.** `encode_rsa_key` writes
  `struct.pack('!II', ...)` then two `encode_long(key.num_bits, ...)` values:
  8 + 256 + 256 = 520, and `ALGORITHMS` carries `public_key_num_bytes=8 + 2*2048//8`.
  (same URL)
- **`openssl genrsa` defaults to exponent 65537 — unverified this pass** (the man
  page was not re-fetched). It is the long-standing default and avbtool will refuse
  the key loudly if it is not, so the risk is nil; the `wc -c` check on the blob
  catches the size half.

### §3 The three verification partitions

- **`--include_descriptors_from_image` copies, does not recompute — confirmed.** It
  runs `self._parse_image(...)` on the given image and re-encodes the descriptors it
  finds. New detail worth knowing: descriptors that have a `partition_name` are
  deduplicated by type+name, and "only include the last seen descriptor" wins.
  (same URL)
- **`_parse_image` reads a footer if there is one, else a bare vbmeta at offset 0 —
  confirmed.** It tries `AvbFooter(image.read(AvbFooter.SIZE))` at the end, and on
  `struct.error` comments "Nope, just seek back to the start", leaving
  `vbmeta_offset = 0`. So the fallback in §3 for a footerless `boot.img` is sound.
  (same URL)
- **Do not include from the original `vbmeta.img` — confirmed, and it matters.**
  `AvbChainPartitionDescriptor` has a `partition_name`, so it goes through the same
  copy path as any other descriptor: including from the original top-level vbmeta
  would carry the manufacturer's chain descriptors, and their public key, straight
  into ours. (same URL)
- **Chain descriptor rules — confirmed on both sides.** avbtool: three fields split
  on `:` or `'Malformed chained partition'`; `'Rollback index location must be 1 or
  larger.'`; `'Rollback Index Location {} is already in use.'`. libavb: a chain
  descriptor with `rollback_index_location == 0` is rejected as
  `ERROR_INVALID_METADATA`.
  (<https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-18.1/libavb/avb_slot_verify.c>)
- **Locations 1 and 2 — partly.** That index 0 is reserved for the top-level vbmeta
  and chained partitions must be ≥ 1, with duplicates rejected, is confirmed in both
  avbtool and libavb. `BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1` shows up
  in AOSP-derived board configs, but I found no official page assigning 2 to
  `vbmeta_vendor`. Immaterial: the document already says to reproduce the values read
  off this unit, which are 1 and 2.
- **One key everywhere satisfies libavb — confirmed.** libavb compares the chained
  vbmeta's embedded key against the chain descriptor's: "Public key used to sign data
  does not match key in chain partition descriptor." →
  `AVB_SLOT_VERIFY_RESULT_ERROR_PUBLIC_KEY_REJECTED`. (avb_slot_verify.c, same URL)
- **`--padding_size` pads to a multiple — confirmed verbatim:** "If non-zero, pads
  output with NUL bytes so its size is a multiple of NUMBER (default: 0)". The
  assert-the-output-size warning is right: a blob over 65536 would silently become
  131072. (avbtool, same URL)
- **Flags: bit 0 hashtree-disabled, bit 1 verification-disabled, word at offset 120,
  network byte order — confirmed.** `AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED =
  (1 << 0)`, `..._VERIFICATION_DISABLED = (1 << 1)`; summing the header's field
  widths (4+4+4+8+8+4+8×10+8) puts `flags` at byte 120, and "All fields are stored in
  network byte order", so a value of 3 is the single byte at 123 — exactly the byte
  ticket 24 changed. The same arithmetic puts `algorithm_type` at offset 28, as §"Still
  to read" says.
  (<https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-18.1/libavb/avb_vbmeta_image.h>)
- **Descriptor order differs but does not matter — confirmed on the consuming side.**
  `GetHashtreeDescriptor` walks every loaded vbmeta and every descriptor, matching on
  partition name, so order is irrelevant. The claim about avbtool's exact emission
  order (chains, then properties, then a sorted dict) is only **partly** verified: the
  dedup dict is quoted, the sort is not.
  (<https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/fs_mgr/libfs_avb/avb_util.cpp>)
- **One addition, not an error.** Signing the per-image appended vbmeta
  (`--algorithm`/`--key` on `add_hashtree_footer`) is **not required for booting**:
  init never reads it, it reads the descriptors out of the three vbmeta partitions.
  It is still worth doing, because `verify_image --key` then checks that image too.
  Nothing to change in §3; worth knowing if a signing step ever has to be dropped.

### §4 What init requires — the most load-bearing section, all confirmed

- **No userspace key check on the top-level vbmeta — confirmed verbatim.** fs_avb's
  own comment: "we have *dummy* operations in FsManagerAvbOps such that
  avb_ops->validate_vbmeta_public_key() used to validate the public key of the
  top-level vbmeta always pass in userspace here."
  (<https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/fs_mgr/libfs_avb/fs_avb.cpp>)
- **The digest check is the live one, and `VERIFICATION_DISABLED` is what switches it
  off — confirmed.** `AvbVerifier` reads `vbmeta.size`, `vbmeta.hash_alg` and
  `vbmeta.digest` via `fs_mgr_get_boot_config`, hashes every loaded vbmeta struct in
  order, and compares both the total size ("total vbmeta size mismatch: ") and the
  digest ("vbmeta digest mismatch"). `Open()` skips all of it when
  `AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED` is set (status becomes
  `kVerificationDisabled`); otherwise a failure logs "VerifyVbmetaImages failed" and
  returns `nullptr`. Note the digest check is **not** softened by an unlocked device —
  only the key-rejection path is. So point 3 of the summary stands as written, and it
  is the right thing to have flagged as the new risk. (same URL)
- **The failure propagates to a panic — confirmed verbatim.** `InitAvbHandle` logs
  "Failed to open AvbHandle" and returns false; `SetUpDmVerity` returns false;
  `first_stage_init.cpp` has `LOG(FATAL) << "Failed to mount required partitions
  early ...";` directly after `if (!DoFirstStageMount()) {`.
  (<https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/init/first_stage_init.cpp>)
- **Hashtree descriptors only, and the table is built from their fields —
  confirmed.** `ConstructVerityTable` passes `image_size / 512` sectors,
  `dm_verity_version`, `data_block_size`, `hash_block_size`,
  `image_size / data_block_size`, `tree_offset / hash_block_size`, the algorithm, the
  root digest and the salt, and adds FEC only under `if (hashtree_desc.fec_size > 0)`.
  (avb_util.cpp, same URL)
- **The fstab `avb` flag — partly; fixed in place.** The consequence the document
  draws is right (the value only makes init create the block device; what loads
  `vbmeta_system`/`vbmeta_vendor` is the chain descriptors), and the comment is quoted
  correctly: "Any partitions needed for verifying the partitions used in first stage
  mount, e.g. vbmeta must be provided as vbmeta_partitions." But bare `avb` is matched
  by the exact-match flag table, not by prefix; only `avb=<name>` reaches the
  `StartsWith(flag, "avb")` branch. `avb_keys=` is tested first and does **not** set
  the `avb` boolean. Corrected in §4.
  (<https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/fs_mgr/fs_mgr_fstab.cpp>,
  <https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/init/first_stage_mount.cpp>)
- **`avb_keys=` is a different, key-matching path — confirmed.** `SetUpDmVerity`
  comments "In this case, try avb_keys first, then fallback to avb flag", and the
  `avb_keys` overload fails with "Expected public key path doesn't exist: " when the
  key file is missing. So reading the fstab really is a precondition, as §"Still to
  read" says. (fs_avb.cpp and first_stage_mount.cpp, same URLs)
- **Wrong root hash → reboot loop — confirmed for the mechanism, with one caveat now
  added.** `ConstructVerityTable` contains
  `if (!fs_mgr_get_boot_config("veritymode", &verity_mode)) { verity_mode =
  "enforcing"; // Defaults to enforcing when it's absent.`, and maps `enforcing` →
  `restart_on_corruption`, `logging` → `ignore_corruption`, `eio` → nothing ("Default
  dm_verity_mode is eio"). The kernel documents `restart_on_corruption` as "Restart
  the system when a corrupted block is discovered" and adds that it "requires user
  space support to avoid restart loops" — which is exactly the predicted outcome.
  **Caveat:** this unit's bootloader very likely sets `androidboot.veritymode`
  explicitly, so the default is probably not what applies. Added as item 6 of
  "Still to read": if it says `eio`, a wrong root hash gives a booting device full of
  read errors rather than a reboot loop, which is a different thing to recognise on
  the day. (avb_util.cpp, same URL;
  <https://docs.kernel.org/admin-guide/device-mapper/verity.html>)
- **One misleading citation, flagged not removed.**
  <https://source.android.com/docs/security/features/verifiedboot/dm-verity> describes
  the *pre-AVB* scheme — a signed dm-verity table, "A public key is included on the
  boot partition", and "If verification fails, the device generates an I/O error".
  None of that is this device's path, and its EIO sentence contradicts the
  `restart_on_corruption` mapping. The authorities for §4 are `avb_util.cpp` and the
  kernel page; treat that page as background only.
- **Rollback indexes are not enforced in userspace — confirmed.** fs_avb notes the
  dummy `read_rollback_index()` always returns zero. (fs_avb.cpp, same URL)
- **The `security_patch` property claim — partly.** `fs_avb.cpp` does build a property
  name and read it with `PropertyDescriptor(avb_prop_name, vbmeta_images_)`, so a
  `com.android.build.<partition>.security_patch` property is read; I did not re-read
  which callers use `GetSecurityPatchLevel`. Immaterial — the conclusion (carry the
  properties over for honesty, nothing boots or fails on them) holds either way.

### §5 Error correction

- **Optional at every level — confirmed.** `--do_not_generate_fec` exists; the table
  gets FEC only under `if (hashtree_desc.fec_size > 0)`; the kernel's FEC is "optional"
  and reached through `use_fec_from_device`, with `fec_roots` defined as "The number of
  parity bytes in each 255-byte Reed-Solomon codeword" — so 2 roots is RS(255, 253),
  as stated. (avbtool; avb_util.cpp; kernel verity page)
- **A corrected block is re-checked before use — confirmed verbatim:** "dm-verity
  validates any FEC-corrected block against the wanted hash before using it", and the
  kernel page concludes FEC therefore does not affect dm-verity's security properties.
  (<https://docs.kernel.org/admin-guide/device-mapper/verity.html>)
- **avbtool needs an external `fec` binary — confirmed.** `generate_fec_data` runs
  `['fec', '--encode', '--roots', str(num_roots), image_filename, fec_tmpfile.name]`
  and `calc_fec_data_size` runs
  `['fec', '--print-fec-size', str(image_size), '--roots', str(num_roots)]`; the
  build definition declares `required: ["fec"]`. Corrected the command line in
  "Tooling", which had the size argument missing.
  (avbtool;
  <https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-18.1/Android.bp>)
- **One qualification added to §7.** `ConstructVerityTable` has
  `// Always use ignore_zero_blocks.` followed by `target.IgnoreZeroBlocks();`, and
  the kernel defines that as "Do not verify blocks that are expected to contain
  zeroes and always return zeroes instead". So "every block is checked on read" is
  very slightly too strong; noted in §7. (avb_util.cpp; kernel verity page)

### §6 The script and its checks

- **`verify_image` really does regenerate and compare the tree — confirmed, with the
  attribution fixed.** `verify_image` itself checks the signature, compares the
  embedded key against `--key` ("Embedded public key does not match given key."),
  handles `--expected_chain_partition` and `--follow_chain_partitions` (both exist,
  the former with metavar `PART_NAME:ROLLBACK_SLOT:KEY_PATH`), and delegates each
  descriptor to `desc.verify(...)`. The regeneration is in
  `AvbHashtreeDescriptor.verify`, which calls `generate_hash_tree` and compares both
  `root_digest` and `hash_tree != hash_tree_ondisk`. Fixed in §6: the success line is
  avbtool's format string, not README example output.
- **It does not verify the error correction — confirmed verbatim:** "TODO(zeuthen):
  we could also verify that the FEC stored in the image is correct but this a)
  currently requires the 'fec' binary; and b) takes a long time; and c) is not
  strictly needed for verification purposes as we've already verified the root hash."
  (avbtool, same URL)
- **`calculate_vbmeta_digest` — confirmed, with one requirement the script met by
  luck.** Default `--hash_algorithm sha256`; it hashes the top-level blob then each
  chained blob in descriptor order (the same order `AvbVerifier` uses), and finds them
  as `os.path.join(image_dir, desc.partition_name + image_ext)`. So `vbmeta.img`,
  `vbmeta_system.img` and `vbmeta_vendor.img` must share a directory and extension.
  Said explicitly in §6 now. (avbtool, same URL)
- **The root-hash equality check as the first thing to run — confirmed as sound, and
  it is the best idea in the document.** Nothing in the hash tree depends on the key
  (the descriptor's `root_digest` comes from `generate_hash_tree` over data, salt,
  algorithm and block size alone), so rebuilding over untouched filesystems must
  reproduce the manufacturer's root hashes. My own reproduction of the six tree and
  FEC sizes is a weaker form of the same test already passing.
- **Two-pass order on the device — confirmed as reasonable, still [Medium].** It
  follows from the rest and nothing refutes it. It does rest on the one thing no
  source can settle: that this bootloader keeps recomputing and reporting a digest
  that matches what init computes. Ticket 24's evidence is the only evidence, and it
  is good evidence.

### §7 Honest limits

Nothing to refute. Everything in the "does not protect against" list is confirmed by
the sources above: no userspace key check, dummy rollback index, a bootloader that
demonstrably accepts an edited vbmeta, and `--flags 3` being one 128 KB write away.
"Integrity checking with a key we control, not verified boot" is the accurate phrase.

### Tooling

- **Python 2 only — confirmed twice over.** AOSP's own copy contains
  `b = 2L**32  # pylint: disable=long-suffix`, `AvbFooter.MAGIC = 'AVBf'` as a `str`,
  and the build definition has `py2: { enabled: true, embedded_launcher: true }` with
  `py3: { enabled: false }`. Pinning 1.1.0 is right. (AOSP avbtool; Android.bp)
- **`avbtool 1.1.0` — confirmed.** `AVB_VERSION_MAJOR = 1`, `AVB_VERSION_MINOR = 1`,
  `AVB_VERSION_SUB = 0`, and `get_release_string()` formats exactly
  `'avbtool {}.{}.{}'`, matching the release string recorded on this unit. (avbtool)
- **OpenSSL 3.x removing `rsautl` — unverified this pass**, and it does not matter on
  Ubuntu 20.04's 1.1.1.

## Built and verified on the PC (2026-10-22)

Scripts in `HY320/scripts/verity/`: `setup.sh` (fetch the tool, generate the key), `build.sh` (hash trees), `build_vbmeta.sh` (the top-level partition), `check2.sh` (the real check), `rebuild_super.py` (write the signed partitions back into the container).

- **The tool** is Google's own `avbtool`, fetched from the Android 11 branch: version **1.1.0**, the same version that built this unit's original data. It is a Python 2 script, so Python 2 was installed in WSL to run it unmodified.
- **Our key**: a fresh 2048-bit RSA key, exponent 65537, no passphrase, at `/usr/local/src/hy320-verity/hy320_avb.pem` inside WSL. Its public blob is 520 bytes, exactly what the original chain descriptors carried.
- **The hash trees reproduce the originals field for field**: system filesystem 1,028,796,416 with a tree of 8,110,080; vendor 113,328,128 / 901,120; product 318,095,360 / 2,510,848; SHA-1, 4096-byte data and hash blocks, the unit's own salt, dm-verity version 1. Each partition came out at exactly its partition size. Only the root digests differ, which is the point.
- **The three verification partitions mirror the original layout**: the top-level one is 128 KB and carries the hashes for boot, dtbo and vendor_boot, product's tree, the seven properties and the two chain descriptors at rollback locations 1 and 2; the chained ones are 64 KB each and carry system's and vendor's trees. The duplicated properties of a first attempt were removed, because the boot images already carry theirs in their own footers.
- **Checked properly**: every tree was recomputed from the image content and matched, the chain was followed from the top-level partition down through both chained ones, and the unchanged boot, dtbo and vendor_boot images still verify against their descriptors. A first check script reported success wrongly, because a pipe swallowed the exit status; `check2.sh` tracks it properly.
- **The container was rebuilt** from the original 2 GB image with the three signed partitions written over their own extents (system is in four pieces, vendor and product in two each), the layout untouched, and each one read back out and compared: all three match.

Ready to write, in `<backup>\signed\`: `super-cleaned.img` (2 GB), `vbmeta.img`, `vbmeta_system.img`, `vbmeta_vendor.img`. The undo for each is in the golden backup.

**One thing deliberately left out: error correction.** The tool computes it by calling a small AOSP helper (`fec`) that is not installed and does not build without the Android build system. The system is fully checked without it: every block is still hashed and a changed block is still detected. What is missing is the ability to repair a few bad blocks by itself, which the original firmware had. It can be added later by building that helper and re-running `build.sh` with `FEC="--fec_num_roots 2"`; the descriptors would then carry the error-correction sizes the original had (8,200,192 / 909,312 / 2,539,520 bytes). Worth raising with the user, not worth blocking on.
