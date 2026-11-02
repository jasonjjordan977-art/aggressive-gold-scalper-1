import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";

export const terminals = sqliteTable('terminals', {
  id: text('id').primaryKey(),
  controlHash: text('control_hash').notNull().unique(),
  bridgeHash: text('bridge_hash').notNull().unique(),
  bridgeToken: text('bridge_token').notNull(),
  config: text('config').notNull(),
  telemetry: text('telemetry'),
  lastSeen: integer('last_seen').notNull().default(0),
  createdAt: integer('created_at').notNull(),
});
export const tradeEvents = sqliteTable('trade_events', {
  id: text('id').primaryKey(),
  terminalId: text('terminal_id').notNull(),
  message: text('message').notNull(),
  createdAt: integer('created_at').notNull(),
});

/**
 * Define your database schema here, then apply it with `bun run db:push`
 * (from packages/web). Re-export any generated schema from this file
 * (e.g. Better Auth's auth-schema.ts) so drizzle generates complete migrations.
 * Table patterns and conventions: skills/app/references/api.md
 */
