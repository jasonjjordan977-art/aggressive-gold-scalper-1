# AGGRESSIVE GOLD SCALPER — Expo SDK 58 upgrade

## Use this replacement source ZIP

`AGGRESSIVE-GOLD-SCALPER-Expo-SDK58-Full-Source.zip` replaces the earlier SDK 54 export. It contains the full workspace: Expo mobile app, backend, companion website, desktop source, MT5 EA, fonts and branded assets. No APK or signing credentials are included.

### Update your GitHub repository

1. Extract the ZIP. Copy the **contents** of its `AGGRESSIVE-GOLD-SCALPER` folder to your repository root, preserving `packages/mobile`, `packages/web`, hidden configuration, `bun.lock` and the new `bunfig.toml`. Do not upload only the ZIP or only the mobile folder.
2. Before replacing `packages/mobile/app.json`, retain your existing Expo `owner` and `extra.eas.projectId` if already linked. Merge them into the new config. Keep your registered platform identifiers and production backend URL where applicable. The Runable application ID is not an Expo project UUID.
3. Use Node 22.13+ on the Node 22 line, Node 24.3+ on the Node 24 line, or Node 26+. Node 23/25 are not supported SDK 58 lines. Install Bun and run `bun install` at the repository root. Keep the hoisted linker configuration.
4. Commit the updated source and lockfile. Set the Expo GitHub project's base directory to `packages/mobile`.

For an exported project built with EAS CLI, run these commands in `packages/mobile` after installing workspace dependencies:

```sh
npx eas-cli@latest login
# Only if not already linked to your own Expo project:
npx eas-cli@latest init
npx eas-cli@latest build --platform android --profile preview
```

`preview` requests an installable Android APK. Complete an initial successful EAS build from the CLI for the selected platform before relying on Expo's GitHub build flow. Existing linked projects should not be re-created. EAS cloud build/signing/queue requirements apply; no cloud build was launched here.

For the managed Runable project, use **Publish** in the mobile preview and connect your Expo account there.

## Changes

- Expo `~58.0.22`, React Native `0.88.1`, React/React DOM `19.3.0`, Expo Router `~58.0.29`, SDK-compatible Expo modules and mobile TypeScript `~6.0.3`.
- Aligned website React versions and added root `bunfig.toml` with `linker = "hoisted"` to avoid duplicate native modules/React installations.
- Removed obsolete architecture and Android edge-to-edge configuration flags. SDK 58 uses the new architecture.
- Migrated splash settings to the `expo-splash-screen` plugin and set a light status bar using its plugin.
- Explicitly retained Expo web client-side output with `web.output = "single"`.
- Set preview Android and production Android/iOS EAS build images to `latest`.
- Fixed tab-icon color typing and an empty-string conditional rendering warning in the notice banner. UI and trading strategy are otherwise unchanged.
- Replaced the invalid underscore in the iOS bundle identifier: `com.goldscalper_g8k2.runable` → `com.goldscalper-g8k2.runable`. Android remains `com.goldscalper_g8k2.runable`. Preserve an existing valid registered iOS identifier if you already have one.

## Verification and limits

Passed: Expo dependency check; Expo Doctor **20/20**; all workspace typechecks; lint; web/desktop builds; web/iOS/Android JavaScript bundle exports; backend integration test with **15 assertions**; browser navigation through all four tabs; disconnected Start protection; backend response. Browser console/page errors: **none** in that test.

The iOS/Android exports used `--no-bytecode` to check bundling; they are **not** native compilation, signed builds or installed-device tests. APK/IPA builds, native device runtime, MetaEditor compilation, real MT5 integration and strategy profitability remain unverified. No live trades were initiated.

## Backend and MT5 still required

The source config retains the development preview backend URL. That URL is not a permanent hosting guarantee. Publish/configure the managed backend through Runable, or host the included backend independently with a persistent database and configure your exported app's `extra.apiUrl` to a permanent HTTPS address before production builds. Do not change platform-managed config inside Runable manually.

Private environment values, databases, pairing keys, caches, dependencies and build output are deliberately excluded. For independent hosting, create your own private root `.env` using `.env.template`; never commit secrets or put database credentials into public Expo variables.

The phone app controls the EA; it does not run MT5. Compile `mt5/AGGRESSIVE_GOLD_SCALPER.mq5` in Windows MetaEditor and follow `mt5/SETUP.md`. Keep MT5 running, allow the backend HTTPS origin for WebRequest, and demo-test before live use. Stop pauses new entries rather than closing positions. Risk limits do not guarantee a maximum loss.

## References

- SDK upgrades: https://docs.expo.dev/workflow/upgrading-expo-sdk-walkthrough/
- SDK 58: https://expo.dev/changelog/sdk-58
- Monorepos: https://docs.expo.dev/build-reference/build-with-monorepos/
- GitHub builds: https://docs.expo.dev/build/building-from-github/
- Android APK: https://docs.expo.dev/build-reference/apk/