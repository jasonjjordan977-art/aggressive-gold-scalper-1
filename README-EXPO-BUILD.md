# AGGRESSIVE GOLD SCALPER — full Expo source export

This archive contains the complete Bun workspace, not just the MT5 Expert Advisor. Keep the directory structure intact: the Expo app is `packages/mobile`, and it imports backend **types** from the workspace package `packages/web`.

## Included

- All Expo React Native screens, Start/Stop controls, pairing logic, and risk settings.
- `packages/mobile/app.json`: app name, icon/splash configuration, platform identifiers, and backend URL.
- `packages/mobile/eas.json`: an Android APK `preview` profile and a `production` profile.
- `packages/mobile/assets/`: branded gold lightning icon, adaptive icon, splash image, favicon, five Manrope font weights and the Ionicons icon font.
- `packages/mobile/constants/theme.ts` and `components/TradingScreen.tsx`: the dark/gold visual styling. Color values also appear in component styles.
- `design.md`: palette and visual design brief.
- `packages/web`: the Hono/oRPC backend, database schema, downloads page, web styling and fonts.
- `mt5`: the Expert Advisor source and its installation/safety guide.
- Root `package.json`, `bun.lock`, workspace configuration and source tests.

The chart artwork is drawn in code using `react-native-svg`; it is not a missing image file. UI icons come from Ionicons. Fonts remain declared package dependencies and are bundled by Expo; copies of the used font files are also supplied in `assets/fonts` for reference.

Excluded deliberately: private `.env` files, API keys, database contents, pairing credentials, signing certificates, node_modules, caches and build output. Run `bun install` to restore dependencies. Signing credentials belong to your own Expo/Apple/Google account.

## Supported build path on Runable

Open the mobile preview's **Publish** option, connect your Expo account, and trigger the Android/iOS build there. This source ZIP is an additional export, not an APK, AAB or IPA. No native binary has been built or verified here.

## If you build the exported source yourself with Expo EAS

Use Expo's cloud builders rather than expecting Expo Go to generate a standalone binary. Install Bun and extract the **whole** archive. Do not copy only `packages/mobile` into another folder.

1. From the extracted workspace root, restore the dependencies:

   ```sh
   bun install
   ```

2. Follow the current Expo setup documentation to install/sign into EAS CLI and link the app to **your own** Expo project. Run EAS commands from `packages/mobile`, where `app.json` and `eas.json` are located. Your Expo project UUID is not supplied in this export; let EAS initialise/link it for you. Do not confuse the existing Runable `applicationId` with an Expo project ID.

3. For an installable Android APK, request the `preview` cloud build:

   ```sh
   eas build --platform android --profile preview
   ```

   The profile specifies `distribution: internal` and `android.buildType: apk`. For Google Play distribution, use the `production` profile instead; Expo normally generates an Android App Bundle for that profile. iOS distribution requires your own Apple signing/provisioning setup and the appropriate EAS build profile.

Expo requires a configured local project/account; this is not a one-file ZIP upload service. Build queues, quotas and signing requirements depend on your accounts. Refer to Expo's current documentation if CLI prompts or requirements differ.

## Important: configure a permanent backend before a production build

The exported `packages/mobile/app.json` currently points `expo.extra.apiUrl` at the Runable **preview** backend used during development. A preview URL is not a production/24-hour service guarantee.

Publish the backend through Runable, or host the included backend yourself with a persistent database. For your independently hosted exported copy, set `expo.extra.apiUrl` to your permanent HTTPS backend **before** building. The client gives that app-config value priority over `EXPO_PUBLIC_API_URL`. If you keep using the managed Runable project, use its publishing/configuration controls rather than changing platform-managed values.

If hosting the backend independently, create a private `.env` file at the workspace root using `.env.template` as a reference. Supply your own `DATABASE_URL` and, when required by the database provider, `DATABASE_AUTH_TOKEN`. Never put database credentials into the mobile app or its public Expo environment. The trading API itself does not need MetaApi, AI gateway, payment or broker-password credentials.

The standalone phone app still needs the reachable backend and a running Windows MT5 terminal. An APK does not embed MT5 or execute the MQL5 EA inside Android/iOS.

## MT5 setup and verification

Read `mt5/SETUP.md`. Compile `AGGRESSIVE_GOLD_SCALPER.mq5` in **MetaEditor**, not Expo. Pair the EA with the phone app, enable Algo Trading, and test on a demo account first. No broker login/password is included in this archive.

Verified before export: app/backend TypeScript checks, root build, lint, browser UI and backend integration tests. Not verified: native EAS builds, MetaEditor compilation, broker execution, continuous production hosting or strategy profitability.

## Expo references

- Setup: https://docs.expo.dev/build/setup/
- APK profiles: https://docs.expo.dev/build-reference/apk/
- EAS configuration: https://docs.expo.dev/build/eas-json/
- Monorepos: https://docs.expo.dev/build-reference/build-with-monorepos/