"use strict";

/**
 * server.js – Entry point for the DevOps Assessment Node.js application.
 *
 * Features:
 *  - Express HTTP server on port 80 (or PORT env var)
 *  - /health endpoint for ALB health checks
 *  - /api/info  endpoint showing environment metadata
 *  - /api/db    endpoint to verify RDS connectivity
 *  - Helmet security headers
 *  - Morgan access logging via Winston
 *  - Graceful shutdown on SIGTERM / SIGINT
 */

require("dotenv").config();

const express = require("express");
const helmet  = require("helmet");
const morgan  = require("morgan");
const mysql   = require("mysql2/promise");
const logger  = require("./logger");

const app  = express();
const PORT = process.env.PORT || 80;

// ── Security headers ─────────────────────────────────────────────────────────
app.use(helmet());
app.disable("x-powered-by");

// ── Request logging ──────────────────────────────────────────────────────────
app.use(
  morgan("combined", {
    stream: { write: (msg) => logger.http(msg.trim()) },
  })
);

app.use(express.json());

// ── Database connection pool ─────────────────────────────────────────────────
let pool;

async function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host:               process.env.DB_HOST,
      port:               parseInt(process.env.DB_PORT || "3306", 10),
      user:               process.env.DB_USER,
      password:           process.env.DB_PASS,
      database:           process.env.DB_NAME,
      ssl:                { rejectUnauthorized: true }, // enforce TLS
      connectionLimit:    10,
      waitForConnections: true,
      queueLimit:         0,
    });
  }
  return pool;
}

// ── Routes ───────────────────────────────────────────────────────────────────

/**
 * GET /health
 * ALB target group health check – must return 200 to be considered healthy.
 */
app.get("/health", (_req, res) => {
  res.status(200).json({
    status:    "ok",
    timestamp: new Date().toISOString(),
    uptime:    process.uptime(),
  });
});

/**
 * GET /api/info
 * Returns basic environment and instance metadata.
 */
app.get("/api/info", (req, res) => {
  res.json({
    project:     process.env.npm_package_name || "devops-assessment-app",
    version:     process.env.npm_package_version || "1.0.0",
    environment: process.env.NODE_ENV || "unknown",
    region:      process.env.AWS_REGION || "unknown",
    node:        process.version,
    hostname:    require("os").hostname(),
    uptime:      process.uptime(),
  });
});

/**
 * GET /api/db
 * Verifies database connectivity by running a lightweight ping query.
 */
app.get("/api/db", async (_req, res) => {
  try {
    const db = await getPool();
    const [rows] = await db.execute("SELECT 1 AS alive, NOW() AS server_time");
    res.json({ status: "connected", result: rows[0] });
  } catch (err) {
    logger.error("Database connectivity check failed", { error: err.message });
    res.status(503).json({ status: "error", message: "Database unavailable" });
  }
});

/**
 * GET /api/items
 * Placeholder CRUD endpoint – returns a static list.
 */
app.get("/api/items", async (_req, res) => {
  try {
    const db = await getPool();
    const [rows] = await db.execute("SELECT * FROM items LIMIT 100");
    res.json({ count: rows.length, items: rows });
  } catch (err) {
    logger.error("Failed to fetch items", { error: err.message });
    res.status(500).json({ error: "Internal server error" });
  }
});

// ── 404 handler ──────────────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

// ── Global error handler ─────────────────────────────────────────────────────
app.use((err, _req, res, _next) => {
  logger.error("Unhandled error", { error: err.message, stack: err.stack });
  res.status(500).json({ error: "Internal server error" });
});

// ── Start server ─────────────────────────────────────────────────────────────
const server = app.listen(PORT, () => {
  logger.info(`Server listening on port ${PORT}`, {
    environment: process.env.NODE_ENV,
    region:      process.env.AWS_REGION,
  });
});

// ── Graceful shutdown ────────────────────────────────────────────────────────
const shutdown = (signal) => {
  logger.info(`Received ${signal} – shutting down gracefully`);
  server.close(async () => {
    if (pool) {
      await pool.end();
      logger.info("Database pool closed");
    }
    logger.info("HTTP server closed");
    process.exit(0);
  });

  // Force exit if graceful shutdown takes > 10s
  setTimeout(() => {
    logger.error("Forced shutdown after timeout");
    process.exit(1);
  }, 10_000);
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT",  () => shutdown("SIGINT"));
