#!/usr/bin/env node
/**
 * Minimal in-memory Linear GraphQL stand-in.
 *
 * Exists so the dedup protocol in runtime-template/linear/client.sh can be
 * proven end to end without credentials and without writing to a real
 * workspace. It implements only the operations client.sh issues, matched by
 * substring on the query text — enough to exercise search/create/comment/
 * reopen and the full `file` protocol.
 *
 * Usage: node test/mock-linear.js <port> [state-file]
 */

const http = require("http");
const fs = require("fs");

const port = Number(process.argv[2] || 4747);
const stateFile = process.argv[3];

const db = { issues: [], comments: [], counter: 0 };

const STATES = [
  { id: "state-unstarted", type: "unstarted" },
  { id: "state-started", type: "started" },
  { id: "state-done", type: "completed" }
];

function reply(res, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(body);
}

function handle({ query, variables = {} }) {
  // searchIssues(term:) — client.sh filters on description client-side, so
  // returning everything is a faithful worst case for the dedup logic.
  if (query.includes("searchIssues")) {
    return {
      data: {
        searchIssues: {
          nodes: db.issues.map((issue) => ({
            id: issue.id,
            identifier: issue.identifier,
            description: issue.description,
            state: { type: issue.stateType }
          }))
        }
      }
    };
  }

  if (query.includes("issueCreate")) {
    db.counter += 1;
    const issue = {
      id: `id-${db.counter}`,
      identifier: `GOD-${db.counter}`,
      title: variables.t,
      description: variables.d,
      teamId: variables.team,
      stateType: "unstarted",
      url: `https://linear.app/mock/issue/GOD-${db.counter}`
    };
    db.issues.push(issue);
    return {
      data: {
        issueCreate: {
          success: true,
          issue: { identifier: issue.identifier, url: issue.url }
        }
      }
    };
  }

  if (query.includes("commentCreate")) {
    db.comments.push({ issueId: variables.i, body: variables.b });
    return { data: { commentCreate: { success: true } } };
  }

  if (query.includes("workflowStates")) {
    return { data: { workflowStates: { nodes: STATES } } };
  }

  if (query.includes("issueUpdate")) {
    const issue = db.issues.find((candidate) => candidate.id === variables.i);
    if (issue) {
      const state = STATES.find((candidate) => candidate.id === variables.s);
      issue.stateType = state ? state.type : issue.stateType;
    }
    return { data: { issueUpdate: { success: Boolean(issue) } } };
  }

  if (query.includes("issues(filter")) {
    return {
      data: {
        issues: {
          nodes: db.issues
            .filter((issue) => !["completed", "canceled"].includes(issue.stateType))
            .map((issue) => ({ title: issue.title }))
        }
      }
    };
  }

  return { errors: [{ message: `mock: unhandled query ${query.slice(0, 60)}` }] };
}

const server = http.createServer((req, res) => {
  // Control endpoints the tests use to inspect and manipulate mock state.
  if (req.url === "/__dump") {
    return reply(res, db);
  }
  if (req.url.startsWith("/__close/")) {
    const identifier = decodeURIComponent(req.url.split("/").pop());
    const issue = db.issues.find((candidate) => candidate.identifier === identifier);
    if (issue) {
      issue.stateType = "completed";
    }
    return reply(res, { closed: Boolean(issue) });
  }

  let raw = "";
  req.on("data", (chunk) => {
    raw += chunk;
  });
  req.on("end", () => {
    let payload;
    try {
      payload = JSON.parse(raw);
    } catch (error) {
      return reply(res, { errors: [{ message: "bad json" }] });
    }
    const result = handle(payload);
    if (stateFile) {
      fs.writeFileSync(stateFile, JSON.stringify(db, null, 2));
    }
    reply(res, result);
  });
});

server.listen(port, () => {
  process.stdout.write(`mock-linear listening on ${port}\n`);
});
