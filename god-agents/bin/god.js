#!/usr/bin/env node

const { spawn } = require("child_process");

const child = spawn("claude", process.argv.slice(2), {
  stdio: "inherit"
});

child.on("error", (error) => {
  if (error.code === "ENOENT") {
    console.error("God: Claude Code was not found.");
    console.error("Install Claude Code first, then run: god");
  } else {
    console.error(`God: failed to start Claude Code: ${error.message}`);
  }
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
  } else {
    process.exit(code ?? 0);
  }
});
