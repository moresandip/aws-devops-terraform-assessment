"use strict";

const request = require("supertest");
const app     = require("../src/server");

// Mock mysql2 so tests don't need a real DB
jest.mock("mysql2/promise", () => ({
  createPool: jest.fn(() => ({
    execute: jest.fn().mockResolvedValue([[{ alive: 1, server_time: new Date() }]]),
    end:     jest.fn().mockResolvedValue(undefined),
  })),
}));

describe("Health Check", () => {
  it("GET /health returns 200 with status ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
    expect(res.body).toHaveProperty("uptime");
    expect(res.body).toHaveProperty("timestamp");
  });
});

describe("API Info", () => {
  it("GET /api/info returns environment metadata", async () => {
    const res = await request(app).get("/api/info");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("node");
    expect(res.body).toHaveProperty("hostname");
  });
});

describe("404 handler", () => {
  it("returns 404 for unknown routes", async () => {
    const res = await request(app).get("/does-not-exist");
    expect(res.status).toBe(404);
    expect(res.body.error).toBe("Not found");
  });
});
