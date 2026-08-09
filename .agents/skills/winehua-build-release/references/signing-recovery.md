# Signing Configuration Recovery

The repo-root `build-profile.json5` (gitignored) and `signs/` were lost with the
old WSL. They are recoverable from Windows-side copies; the reconstruction below
produces a debug HAP whose signature is byte-identical to the pre-loss build.

## Material locations (this machine)

| Item | Location |
| --- | --- |
| Current debug/release profiles + keystores | `F:\PomeloWin\signs` (`Pro_NewDebugDebug.p7b`, `旧柚Pro-正式Release.p7b`, `app_debug.p12/.cer`, `hyperview.p12/.cer`) |
| DevEco key materials (`material/{fd,ac,ce}`) | `F:\MyProject\vintage-pomelo\docs\签名\material` (hyperview), `...\docs\签名\ad\material` (app_debug) |
| Encrypted passwords for hyperview | `C:\Users\liufeng\DevEcoStudioProjects\HyperView\build-profile.json5` |
| Decrypt helper | repo-root `sign.js` (DevEco AES-128-GCM; key derived from `<keystore-dir>/material`) |

## How the scheme works

- `build-profile.json5` stores `keyPassword`/`storePassword` as DevEco-encrypted
  hex strings, not plaintext.
- `sign.py` (used by `package.sh`) decrypts them by running
  `node sign.js <keystore-dir> <encrypted>`.
- Decryption requires the `material` directory next to the keystore. Different
  keystores have different materials (they do NOT share keys).
- Keystore passwords: `app_debug.p12` and `hyperview.p12` share the same
  12-character password; key alias `ad` (app_debug) and `hv` (hyperview).

## Recovery steps

1. Decrypt the hyperview store/key passwords with `sign.js` using
   `...\docs\签名` as base (contains `material/`). Save plaintext to a chmod-600
   file; never print it.
2. Confirm the plaintext opens both p12 files:
   `openssl pkcs12 -in <p12> -passin pass:<plain> -nokeys -noout`.
3. Re-encrypt the plaintext per material. `sign.js` only decrypts; write a small
   `encrypt.js` using the same key derivation (`getKey` from `fd/ac/ce`), format
   `[4-byte len][IV][ciphertext][16-byte tag]`, AES-128-GCM. Verify every
   generated string by round-tripping through `sign.js` (decrypt == plaintext).
4. Lay out `signs/` so each config's `certpath` base directory contains its own
   `material/`:

   ```text
   signs/
     hyperview.cer|p12, pomelo-pro-release.p7b   # release
     material/{fd,ac,ce}                          # hyperview material
     ad/
       app_debug.cer|p12, Pro_NewDebugDebug.p7b  # debug
       material/{fd,ac,ce}                        # app_debug material
   ```

5. `build-profile.json5`: `signingConfigs` = `default` (debug -> `./signs/ad/...`,
   keyAlias `ad`) and `release` (-> `./signs/...`, keyAlias `hv`); `products` =
   `default` + `proRelease` (both `6.1.0(23)`); module `entry` applies to both
   products. `sign.py` picks `signingConfigs[0]` for the debug HAP; `hvigorw
   assembleApp -p product=proRelease` uses the `release` config.
6. Profile file names must be ASCII. Use `pomelo-pro-release.p7b` (the Java
   signing tool mangles Chinese names to `??????`, error `11012002`). The debug
   name `Pro_NewDebugDebug.p7b` is already ASCII.

## Verification

- After `make hap`, `verify-app` on the HAP must succeed; the chain leaf is the
  Huawei development certificate `刘峰(1829801403766320897), Development` and the
  full chain/profile must match the previous release artifacts byte-for-byte.
- A device refusing `install -r` with `install sign info inconsistent
  (9568332)` means the previously installed build used a different debug
  certificate; clean reinstall is required (application data is removed).

## Security rules

- Never print, commit, or archive passwords, encrypted material, p7b contents, or
  certificate keys. `build-profile.json5` is gitignored; `signs/` is excluded via
  `.git/info/exclude` (do not add it to `.gitignore` in a commit).
- Do not route the formal APP through the debug `sign.py` flow.
