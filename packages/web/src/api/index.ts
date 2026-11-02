import type { RouterClient } from "@orpc/server";
import { createApp } from "./__core/app";
import { ping } from "./routes/ping";
import { scalper, heartbeat } from "./routes/scalper";

// API features are oRPC procedures, one file per feature in ./routes/,
// composed into this router — typed end-to-end via the clients
// (web: src/web/lib/api.ts, mobile: lib/api.ts).
// Keep each routes/ file under 500 lines (`bun run lint` enforces this);
// split into more feature files as they grow.
// Patterns and examples: skills/app/references/api.md
export const router = {
  ping,
  scalper,
};

export type AppRouter = typeof router;
/** Typed client for the router — used by the web and mobile api clients. */
export type AppRouterClient = RouterClient<AppRouter>;

const app = createApp(router);
app.post('/api/webhooks/mt5', async (c) => {
  if (Number(c.req.header('content-length') || 0) > 64000) return c.text('too large', 413);
  try {
    const result = await heartbeat(c.req.header('authorization') || '', await c.req.json());
    return c.text(result.body, result.code as 200 | 400 | 401);
  } catch { return c.text('invalid request', 400); }
});
// Rare plain-HTTP endpoints (webhooks, streaming, the Better Auth handler)
// register here with full paths, e.g. app.post("/api/webhooks/example", ...)

export default app;
