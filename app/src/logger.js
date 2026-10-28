"use strict";

const winston = require("winston");

const { combine, timestamp, json, colorize, simple } = winston.format;

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: combine(timestamp(), json()),
  transports: [
    // Console output (captured by CloudWatch agent)
    new winston.transports.Console({
      format:
        process.env.NODE_ENV === "production"
          ? combine(timestamp(), json())
          : combine(colorize(), simple()),
    }),
    // File output (CloudWatch agent tails this)
    new winston.transports.File({
      filename: "/var/log/app/error.log",
      level:    "error",
      silent:   process.env.NODE_ENV === "test",
    }),
    new winston.transports.File({
      filename: "/var/log/app/combined.log",
      silent:   process.env.NODE_ENV === "test",
    }),
  ],
});

module.exports = logger;
