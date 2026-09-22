#!/usr/bin/env node
"use strict";

/**
 * God Zen's daily wellbeing report.
 *
 * Collects timestamps and counts — never content — from three local sources: git commits
 * authored by the user, Claude Code token usage, and Apple Health sleep exported to iCloud.
 * Timestamps gathered from MCP tools (calendar, Slack, Gmail, Linear, Notion) are passed in
 * by the skill with --mcp. Everything is scored by scripts/zen-score.js and printed as one
 * terminal report. Nothing is ever uploaded and nothing leaves ~/.god-zen.
 *
 * Usage:
 *   node zen-report.js [--mcp '<json>'] [--mcp-file <path>] [--date YYYY-MM-DD] [--json] [--rebuild]
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");
const score = require("./zen-score");

const HOME = os.homedir();
const DIR = path.join(HOME, ".god-zen");
const CONFIG_FILE = path.join(DIR, "config.json");
const HISTORY_FILE = path.join(DIR, "history.jsonl");
const SEEN_FILE = path.join(DIR, "quotes-seen.json");
const QUOTES_FILE = path.join(__dirname, "quotes.json");
const QUOTE_COOLDOWN_DAYS = 21;
const QUOTE_RATE = 0.05;
const QUOTE_GAP_DAYS = 3;
const QUOTE_SCORE_CEILING = 6;
const HOOK_ACTIVITY = path.join(HOME, ".claude", "god", "god-zen", "activity.jsonl");
const CLAUDE_PROJECTS = path.join(HOME, ".claude", "projects");
const DAY_MS = 86400000;
const HISTORY_DAYS = 30;
const HISTORY_KEEP_DAYS = 365;
const BASELINE_DAYS = 28;
const SESSION_GAP_MS = 30 * 60000;
const MAX_LOG_BYTES = 256 * 1024 * 1024;
const CHART_MAX = 10;
const CHART_DAYS = 7;
const CHART_CELL = 7;
const CHART_BAR = 5;
const CHART_GUIDES = [5, 8];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const SKIP_DIRS = new Set(["node_modules", "Library", "Applications", "Pictures", "Movies", "Music", ".Trash"]);

const DEFAULT_CONFIG = {
  repoRoots: ["~/Documents", "~"],
  maxDepth: 3,
  authorEmails: [],
  timezone: "Asia/Kolkata",
  dayStartHour: 5,
  healthFolder: "~/Library/Mobile Documents/com~apple~CloudDocs/GodZen/sleep",
  stopBy: "21:00",
  useCcusage: true,
};

/**
 * Expands a leading ~ to the home directory.
 * Args: target (string)
 * Returns: absolute path string
 * Handles: already-absolute paths, empty input
 */
function expandHome(target) {
  if (!target) {
    return target;
  }
  return target.startsWith("~") ? path.join(HOME, target.slice(1)) : target;
}

/**
 * Reads ~/.god-zen/config.json, writing it with defaults on first run.
 * Args: none
 * Returns: config object merged over the defaults
 * Handles: a missing directory, a corrupt file (falls back to defaults without throwing),
 *          an empty authorEmails list (seeded from git's own user.email), a timezone the
 *          machine cannot resolve (replaced by the local one so the header stays honest)
 */
function loadConfig() {
  fs.mkdirSync(DIR, { recursive: true });
  let stored = {};
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      stored = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8"));
    } catch (error) {
      stored = {};
    }
  }
  const config = { ...DEFAULT_CONFIG, ...stored };
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: config.timezone });
  } catch (error) {
    config.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  }
  if (!config.authorEmails.length) {
    const email = run("git", ["config", "--global", "user.email"]);
    config.authorEmails = email ? [email.trim()] : [];
  }
  if (!fs.existsSync(CONFIG_FILE) || JSON.stringify(stored) !== JSON.stringify(config)) {
    fs.writeFileSync(CONFIG_FILE, `${JSON.stringify(config, null, 2)}\n`);
  }
  return config;
}

/**
 * Runs a command and returns its stdout, swallowing every failure.
 * Args: cmd (string), args (string[]), options ({cwd, timeout})
 * Returns: stdout string, or "" when the command is missing, fails or times out
 * Handles: missing binaries, non-zero exits, hung processes, oversized output
 */
function run(cmd, args, options = {}) {
  try {
    return execFileSync(cmd, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: options.timeout || 20000,
      maxBuffer: 64 * 1024 * 1024,
      cwd: options.cwd,
    });
  } catch (error) {
    return "";
  }
}

/**
 * Breaks an epoch into wall-clock parts inside the configured timezone.
 * Args: epochMs (number), timezone (string)
 * Returns: {year, month, day, hour, minute}
 * Handles: an invalid timezone name by falling back to the machine's local zone
 */
function zoned(epochMs, timezone) {
  let parts;
  try {
    parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      hour12: false,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).formatToParts(new Date(epochMs));
  } catch (error) {
    return zoned(epochMs, undefined);
  }
  const get = (type) => Number(parts.find((part) => part.type === type).value);
  return { year: get("year"), month: get("month"), day: get("day"), hour: get("hour") % 24, minute: get("minute") };
}

/**
 * Names the Zen day an instant belongs to; the day runs from dayStartHour to dayStartHour.
 * Args: epochMs (number), config ({timezone, dayStartHour})
 * Returns: "YYYY-MM-DD"
 * Handles: after-midnight work (00:29 belongs to the previous day), month and year rollover
 */
function dayKey(epochMs, config) {
  const local = zoned(epochMs, config.timezone);
  const shifted = local.hour < config.dayStartHour ? epochMs - DAY_MS : epochMs;
  const day = zoned(shifted, config.timezone);
  return `${day.year}-${String(day.month).padStart(2, "0")}-${String(day.day).padStart(2, "0")}`;
}

/**
 * Hours elapsed since the day boundary, so 21:00 on a 05:00 day is 16.
 * Args: epochMs (number), config ({timezone, dayStartHour})
 * Returns: number in [0, 24)
 * Handles: instants before the boundary, which wrap to the end of the previous day
 */
function hoursFromDayStart(epochMs, config) {
  const local = zoned(epochMs, config.timezone);
  const hours = local.hour + local.minute / 60 - config.dayStartHour;
  return hours < 0 ? hours + 24 : hours;
}

/**
 * Formats an instant as HH:MM in the configured timezone.
 * Args: epochMs (number|null), config (object)
 * Returns: "HH:MM" or "—"
 */
function clock(epochMs, config) {
  if (epochMs == null) {
    return "—";
  }
  const local = zoned(epochMs, config.timezone);
  return `${String(local.hour).padStart(2, "0")}:${String(local.minute).padStart(2, "0")}`;
}

/**
 * Shifts a "YYYY-MM-DD" key by whole days.
 * Args: key (string), days (number)
 * Returns: "YYYY-MM-DD"
 * Handles: month and year boundaries via UTC arithmetic on the date alone
 */
function shiftKey(key, days) {
  const [year, month, day] = key.split("-").map(Number);
  const moved = new Date(Date.UTC(year, month - 1, day + days));
  return moved.toISOString().slice(0, 10);
}

/**
 * Finds every git repository under the configured roots.
 * Args: roots (string[]), maxDepth (number)
 * Returns: array of absolute repository paths, de-duplicated
 * Handles: missing roots, permission errors, hidden and vendored folders, nested worktrees
 */
function findRepos(roots, maxDepth) {
  const found = new Set();
  const walk = (dir, depth) => {
    if (depth > maxDepth) {
      return;
    }
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (error) {
      return;
    }
    if (entries.some((entry) => entry.name === ".git")) {
      found.add(dir);
      return;
    }
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.isSymbolicLink()) {
        continue;
      }
      if (entry.name.startsWith(".") || SKIP_DIRS.has(entry.name)) {
        continue;
      }
      walk(path.join(dir, entry.name), depth + 1);
    }
  };
  for (const root of roots) {
    walk(expandHome(root), 0);
  }
  return [...found];
}

/**
 * Collects commit timestamps authored by the user across every repository found.
 * Args: repos (string[]), emails (string[]), sinceEpoch (number)
 * Returns: array of {ts, repo}
 * Handles: repos with no matching commits, an empty email list (returns nothing rather
 *          than every author's commits), corrupt repositories, detached worktrees
 */
function collectGit(repos, emails, sinceEpoch) {
  if (!emails.length) {
    return [];
  }
  const since = new Date(sinceEpoch).toISOString();
  const commits = [];
  for (const repo of repos) {
    const args = ["log", "--all", "--no-merges", `--since=${since}`, "--format=%at"];
    for (const email of emails) {
      args.push(`--author=${email}`);
    }
    const out = run("git", args, { cwd: repo, timeout: 15000 });
    for (const line of out.split("\n")) {
      const seconds = Number(line.trim());
      if (Number.isFinite(seconds) && seconds > 0) {
        commits.push({ ts: seconds * 1000, repo: path.basename(repo) });
      }
    }
  }
  return commits;
}

/**
 * Reads token totals and spend per calendar day from ccusage.
 * Args: sinceEpoch (number), enabled (boolean)
 * Returns: {days: {"YYYY-MM-DD": {tokens, cost}}, ok: boolean}
 * Handles: npx or network being unavailable, a changed JSON shape, a slow first install
 */
function collectCcusage(sinceEpoch, enabled) {
  if (!enabled) {
    return { days: {}, ok: false };
  }
  const since = new Date(sinceEpoch).toISOString().slice(0, 10).replace(/-/g, "");
  const out = run("npx", ["-y", "ccusage@latest", "daily", "--json", "--since", since], { timeout: 120000 });
  if (!out.trim()) {
    return { days: {}, ok: false };
  }
  try {
    const parsed = JSON.parse(out);
    const days = {};
    for (const entry of parsed.daily || []) {
      const key = entry.period || entry.date;
      if (!key) {
        continue;
      }
      const bucket = days[key] || (days[key] = { tokens: 0, cost: 0 });
      bucket.tokens += Number(entry.totalTokens) || 0;
      bucket.cost += Number(entry.totalCost) || 0;
    }
    return { days, ok: Object.keys(days).length > 0 };
  } catch (error) {
    return { days: {}, ok: false };
  }
}

/**
 * Scans Claude Code session logs for activity timestamps and, when asked, token counts.
 * Args: sinceEpoch (number), withTokens (boolean)
 * Returns: {events: [{ts, session, cwd}], tokensByDayStamp: [{ts, tokens}], ok: boolean}
 * Handles: a missing projects folder, files older than the window (skipped by mtime),
 *          a single log too large to hold in memory (skipped), unreadable or truncated
 *          files, logs whose usage fields were pruned
 */
function collectClaudeLogs(sinceEpoch, withTokens) {
  const events = [];
  const tokenStamps = [];
  if (!fs.existsSync(CLAUDE_PROJECTS)) {
    return { events, tokenStamps, ok: false };
  }
  let projects = [];
  try {
    projects = fs.readdirSync(CLAUDE_PROJECTS, { withFileTypes: true });
  } catch (error) {
    return { events, tokenStamps, ok: false };
  }
  for (const project of projects) {
    if (!project.isDirectory()) {
      continue;
    }
    const dir = path.join(CLAUDE_PROJECTS, project.name);
    let files = [];
    try {
      files = fs.readdirSync(dir).filter((name) => name.endsWith(".jsonl"));
    } catch (error) {
      continue;
    }
    for (const name of files) {
      const file = path.join(dir, name);
      let text = "";
      try {
        const stat = fs.statSync(file);
        if (stat.mtimeMs < sinceEpoch || stat.size > MAX_LOG_BYTES) {
          continue;
        }
        text = fs.readFileSync(file, "utf8");
      } catch (error) {
        continue;
      }
      const session = name.replace(/\.jsonl$/, "");
      for (const match of text.matchAll(/"timestamp"\s*:\s*"([^"]+)"/g)) {
        const ts = Date.parse(match[1]);
        if (Number.isFinite(ts) && ts >= sinceEpoch) {
          events.push({ ts, session, cwd: project.name });
        }
      }
      if (!withTokens || !text.includes("output_tokens")) {
        continue;
      }
      const seen = new Set();
      for (const line of text.split("\n")) {
        if (!line.includes("output_tokens")) {
          continue;
        }
        let entry;
        try {
          entry = JSON.parse(line);
        } catch (error) {
          continue;
        }
        const usage = entry.message && entry.message.usage;
        const ts = Date.parse(entry.timestamp);
        if (!usage || !Number.isFinite(ts) || ts < sinceEpoch) {
          continue;
        }
        const key = `${(entry.message && entry.message.id) || ""}:${entry.requestId || ""}`;
        if (key !== ":" && seen.has(key)) {
          continue;
        }
        seen.add(key);
        const tokens =
          (Number(usage.input_tokens) || 0) +
          (Number(usage.output_tokens) || 0) +
          (Number(usage.cache_creation_input_tokens) || 0) +
          (Number(usage.cache_read_input_tokens) || 0);
        tokenStamps.push({ ts, tokens });
      }
    }
  }
  return { events, tokenStamps, ok: events.length > 0 };
}

/**
 * Reads the sleep files the iOS Shortcut writes to iCloud Drive.
 * Args: folder (string)
 * Returns: {"YYYY-MM-DD": {asleepMinutes, bedtime, wake}}
 * Handles: the folder not existing (the Shortcut was never set up), partial or
 *          corrupt files, files whose name does not carry a date
 */
function collectSleep(folder) {
  const dir = expandHome(folder);
  const nights = {};
  if (!dir || !fs.existsSync(dir)) {
    return nights;
  }
  let files = [];
  try {
    files = fs.readdirSync(dir).filter((name) => /^\d{4}-\d{2}-\d{2}\.json$/.test(name));
  } catch (error) {
    return nights;
  }
  for (const name of files) {
    try {
      const entry = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"));
      const minutes = Number(entry.asleep_minutes);
      if (!Number.isFinite(minutes) || minutes <= 0) {
        continue;
      }
      nights[entry.date || name.slice(0, 10)] = {
        asleepMinutes: minutes,
        bedtime: entry.bedtime || null,
        wake: entry.wake || null,
      };
    } catch (error) {
      continue;
    }
  }
  return nights;
}

/**
 * Reads the timestamps the god-zen hook appends on every session, prompt and stop.
 * Args: sinceEpoch (number)
 * Returns: array of epoch milliseconds
 * Handles: the hook never having run, partially written lines
 */
function collectHookActivity(sinceEpoch) {
  if (!fs.existsSync(HOOK_ACTIVITY)) {
    return [];
  }
  const stamps = [];
  try {
    for (const line of fs.readFileSync(HOOK_ACTIVITY, "utf8").split("\n")) {
      if (!line.trim()) {
        continue;
      }
      const ts = Number(JSON.parse(line).ts) * 1000;
      if (Number.isFinite(ts) && ts >= sinceEpoch) {
        stamps.push(ts);
      }
    }
  } catch (error) {
    return stamps;
  }
  return stamps;
}

/**
 * Parses the MCP payload the skill collects from connected tools.
 * Args: raw (string|null)
 * Returns: {timestamps: number[], meetings: [{start, end}], sources: string[]}
 * Handles: no payload at all, invalid JSON, unparseable timestamps — every one is dropped
 *          silently so a missing connector never fails the report
 */
function parseMcp(raw) {
  const empty = { timestamps: [], meetings: [], sources: [] };
  if (!raw) {
    return empty;
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    return empty;
  }
  const stamps = (parsed.timestamps || [])
    .map((value) => (typeof value === "number" ? value : Date.parse(value)))
    .filter(Number.isFinite);
  const meetings = (parsed.meetings || [])
    .map((entry) => ({ start: Date.parse(entry.start), end: Date.parse(entry.end) }))
    .filter((entry) => Number.isFinite(entry.start) && Number.isFinite(entry.end) && entry.end > entry.start);
  return { timestamps: stamps, meetings, sources: parsed.sources || [] };
}

/**
 * Largest number of Claude Code sessions alive at the same moment inside one day.
 * Args: events ([{ts, session}])
 * Returns: integer count
 * Handles: a single event per session (treated as a 30-minute window), sessions that
 *          straddle the day boundary, an empty list
 */
function maxParallelSessions(events) {
  const windows = new Map();
  for (const event of events) {
    const current = windows.get(event.session);
    if (!current) {
      windows.set(event.session, { start: event.ts, end: event.ts });
      continue;
    }
    current.start = Math.min(current.start, event.ts);
    current.end = Math.max(current.end, event.ts);
  }
  const edges = [];
  for (const window of windows.values()) {
    edges.push({ ts: window.start, delta: 1 });
    edges.push({ ts: Math.max(window.end, window.start + SESSION_GAP_MS), delta: -1 });
  }
  edges.sort((a, b) => a.ts - b.ts || a.delta - b.delta);
  let live = 0;
  let peak = 0;
  for (const edge of edges) {
    live += edge.delta;
    peak = Math.max(peak, live);
  }
  return peak;
}

/**
 * Folds every collected source into one record per Zen day.
 * Args: sources (object), config (object), keys (string[]) — the days to build
 * Returns: {"YYYY-MM-DD": dayRecord}
 * Handles: days with no activity anywhere (marked day_off), sources that returned nothing,
 *          tokens falling back from ccusage to the raw session logs
 */
function buildDays(sources, config, keys) {
  const days = {};
  for (const key of keys) {
    days[key] = {
      date: key,
      first_ts: null,
      last_ts: null,
      commits: 0,
      repos: [],
      tokens: 0,
      cost: null,
      sessions: 0,
      max_parallel_sessions: 0,
      sleep_minutes: null,
      bedtime: null,
      wake: null,
      meeting_minutes: null,
      first_meeting: null,
      last_meeting: null,
      day_off: true,
    };
  }
  const touch = (key, ts) => {
    const day = days[key];
    if (!day) {
      return null;
    }
    day.day_off = false;
    day.first_ts = day.first_ts == null ? ts : Math.min(day.first_ts, ts);
    day.last_ts = day.last_ts == null ? ts : Math.max(day.last_ts, ts);
    return day;
  };

  const repoSets = {};
  for (const commit of sources.commits) {
    const key = dayKey(commit.ts, config);
    const day = touch(key, commit.ts);
    if (!day) {
      continue;
    }
    day.commits += 1;
    (repoSets[key] || (repoSets[key] = new Set())).add(commit.repo);
  }
  for (const [key, repos] of Object.entries(repoSets)) {
    days[key].repos = [...repos].sort();
  }

  const sessionEvents = {};
  for (const event of sources.claude.events) {
    const key = dayKey(event.ts, config);
    if (!touch(key, event.ts)) {
      continue;
    }
    (sessionEvents[key] || (sessionEvents[key] = [])).push(event);
  }
  for (const [key, events] of Object.entries(sessionEvents)) {
    days[key].sessions = new Set(events.map((event) => event.session)).size;
    days[key].max_parallel_sessions = maxParallelSessions(events);
  }

  for (const stamp of sources.hookActivity) {
    touch(dayKey(stamp, config), stamp);
  }
  for (const stamp of sources.mcp.timestamps) {
    touch(dayKey(stamp, config), stamp);
  }
  for (const meeting of sources.mcp.meetings) {
    const key = dayKey(meeting.start, config);
    const day = touch(key, meeting.start);
    if (!day) {
      continue;
    }
    touch(key, meeting.end);
    day.meeting_minutes = (day.meeting_minutes || 0) + (meeting.end - meeting.start) / 60000;
    day.first_meeting = day.first_meeting == null ? meeting.start : Math.min(day.first_meeting, meeting.start);
    day.last_meeting = day.last_meeting == null ? meeting.end : Math.max(day.last_meeting, meeting.end);
  }

  if (sources.ccusage.ok) {
    for (const [calendarDay, usage] of Object.entries(sources.ccusage.days)) {
      const day = days[calendarDay];
      if (!day) {
        continue;
      }
      day.tokens = usage.tokens;
      day.cost = usage.cost;
      if (usage.tokens > 0) {
        day.day_off = false;
      }
    }
  } else {
    for (const stamp of sources.claude.tokenStamps) {
      const day = days[dayKey(stamp.ts, config)];
      if (day) {
        day.tokens += stamp.tokens;
      }
    }
  }

  for (const key of keys) {
    const night = sources.sleep[key];
    if (night) {
      days[key].sleep_minutes = night.asleepMinutes;
      days[key].bedtime = night.bedtime;
      days[key].wake = night.wake;
    }
  }
  return days;
}

/**
 * Adds the score and its components to every day, each against its own prior baseline.
 * Args: days (dayRecord[] ordered oldest first), config (object)
 * Returns: the same array, each record carrying score, band, components and baseline
 * Handles: the first days of the window having no baseline (the intensity component is
 *          dropped and its weight redistributed), days off (no score at all)
 */
function scoreDays(days, config) {
  const byDate = new Map(days.map((day) => [day.date, day]));
  for (let index = 0; index < days.length; index += 1) {
    const day = days[index];
    const prior = [];
    for (let back = 1; back <= BASELINE_DAYS; back += 1) {
      const previous = byDate.get(shiftKey(day.date, -back));
      if (previous && !previous.day_off) {
        prior.push(previous);
      }
    }
    const tokenBaseline = score.median(prior.map((entry) => entry.tokens).filter((value) => value > 0));
    const commitBaseline = score.median(prior.map((entry) => entry.commits).filter((value) => value > 0));
    day.baseline = { tokens: tokenBaseline, commits: commitBaseline, days: prior.length };

    let daysOff = 0;
    for (let back = 0; back < 7; back += 1) {
      const entry = byDate.get(shiftKey(day.date, -back));
      if (entry && entry.day_off) {
        daysOff += 1;
      }
    }
    day.days_off_last_7 = daysOff;

    if (day.day_off) {
      day.work_hours = null;
      day.last_activity_hours = null;
      day.past_midnight = false;
      day.components = {};
      day.score = null;
      day.band = score.band(null);
      continue;
    }

    day.work_hours = (day.last_ts - day.first_ts) / 3600000;
    day.last_activity_hours = hoursFromDayStart(day.last_ts, config);
    day.past_midnight = day.last_activity_hours >= 24 - config.dayStartHour;
    day.token_ratio = tokenBaseline ? day.tokens / tokenBaseline : null;
    day.commit_ratio = commitBaseline ? day.commits / commitBaseline : null;
    day.components = {
      dayLength: score.dayLengthScore(day.work_hours),
      sleep: score.sleepScore({
        asleepMinutes: day.sleep_minutes,
        lastActivityHours: day.last_activity_hours,
        dayStartHour: config.dayStartHour,
      }),
      intensity: score.intensityScore({ tokenRatio: day.token_ratio, commitRatio: day.commit_ratio }),
      recovery: score.recoveryScore(daysOff),
    };
    day.score = score.zenScore(day.components, {
      pastMidnight: day.past_midnight,
      sleepHours: day.sleep_minutes == null ? null : day.sleep_minutes / 60,
    });
    day.band = score.band(day.score);
  }
  return days;
}

/**
 * An empty day, used for dates the history has never seen.
 * Args: date (string "YYYY-MM-DD")
 * Returns: a day record marked as a day off with every count at zero
 */
function blankDay(date) {
  return {
    date,
    first_ts: null,
    last_ts: null,
    commits: 0,
    repos: [],
    tokens: 0,
    cost: null,
    sessions: 0,
    max_parallel_sessions: 0,
    sleep_minutes: null,
    bedtime: null,
    wake: null,
    meeting_minutes: null,
    first_meeting: null,
    last_meeting: null,
    day_off: true,
  };
}

/**
 * Reads ~/.god-zen/history.jsonl.
 * Args: none
 * Returns: Map of date to stored record
 * Handles: no history yet, lines corrupted by an interrupted write
 */
function readHistory() {
  const history = new Map();
  if (!fs.existsSync(HISTORY_FILE)) {
    return history;
  }
  for (const line of fs.readFileSync(HISTORY_FILE, "utf8").split("\n")) {
    if (!line.trim()) {
      continue;
    }
    try {
      const entry = JSON.parse(line);
      if (entry.date) {
        history.set(entry.date, entry);
      }
    } catch (error) {
      continue;
    }
  }
  return history;
}

/**
 * Writes the history back, oldest first, keeping only raw numbers and timestamps.
 * Args: days (dayRecord[]), today (string "YYYY-MM-DD")
 * Returns: nothing
 * Handles: an unwritable home directory (the report still prints), scores which are
 *          derived and therefore never persisted, a file that would otherwise grow forever
 *          (anything older than a year is dropped), a crash mid-write (the new file is
 *          staged beside the old one and renamed into place, so a torn read is impossible)
 */
function writeHistory(days, today) {
  const oldest = shiftKey(today, -HISTORY_KEEP_DAYS);
  const lines = days
    .filter((day) => day.date >= oldest)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((day) => {
      const { components, score: value, band: label, baseline, token_ratio, commit_ratio, ...raw } = day;
      return JSON.stringify(raw);
    });
  const temp = `${HISTORY_FILE}.tmp`;
  try {
    fs.writeFileSync(temp, `${lines.join("\n")}\n`);
    fs.renameSync(temp, HISTORY_FILE);
  } catch (error) {
    try {
      fs.rmSync(temp, { force: true });
    } catch (cleanupError) {
      return;
    }
  }
}

/**
 * Rolling mean of the last n scored days ending at an index.
 * Args: days (dayRecord[]), index (number), window (number)
 * Returns: number or null when no day in the window was scored
 */
function rollingAverage(days, index, window) {
  const values = [];
  for (let back = 0; back < window; back += 1) {
    const day = days[index - back];
    if (day && day.score != null) {
      values.push(day.score);
    }
  }
  if (!values.length) {
    return null;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

/**
 * Draws the last seven days as one labelled bar each.
 * Seven fat bars with gaps read at a glance where thirty thin ones blur together; the
 * x-axis carries the date under every bar and its score under that, and the y-axis is the
 * score itself — taller is a better day.
 * Args: daily (number[]), labels (string[]) — one "YYYY-MM-DD" per point, same order
 * Returns: array of printable lines — y-axis 10 down to 1, guides at 5 and 8, an axis,
 *          a date row and a score row
 * Handles: days off (no bar, "off" under the date), an empty series, missing labels
 */
function chart(daily, labels = []) {
  if (!daily.length) {
    return ["  not enough history yet"];
  }
  const lead = Math.floor((CHART_CELL - CHART_BAR) / 2);
  const trail = CHART_CELL - CHART_BAR - lead;
  const width = daily.length * CHART_CELL;
  const lines = [];

  for (let level = CHART_MAX; level >= 1; level -= 1) {
    const guide = CHART_GUIDES.includes(level);
    const background = guide ? "┄" : " ";
    let row = "";
    for (const value of daily) {
      let bar = background;
      if (value != null) {
        if (value >= level) {
          bar = "█";
        } else if (value >= level - 0.5) {
          bar = "▄";
        }
      }
      row += background.repeat(lead) + bar.repeat(CHART_BAR) + background.repeat(trail);
    }
    lines.push(`  ${String(level).padStart(2)} ${guide ? "┼" : "┤"}${row.replace(/\s+$/, "")}`);
  }
  lines.push(`     └${"─".repeat(width)}`);

  const centre = (text) => {
    const clipped = (text || "").slice(0, CHART_CELL);
    const left = Math.floor((CHART_CELL - clipped.length) / 2);
    return " ".repeat(left) + clipped + " ".repeat(CHART_CELL - clipped.length - left);
  };
  lines.push(`      ${daily.map((value, position) => centre(monthDay(labels[position]))).join("").replace(/\s+$/, "")}`);
  lines.push(`      ${daily.map((value) => centre(value == null ? "off" : value.toFixed(1))).join("").replace(/\s+$/, "")}`);
  return lines;
}

/**
 * Wraps text in the terminal's bold sequence when stdout is a TTY.
 * Args: text (string|number)
 * Returns: string
 */
function bold(text) {
  return process.stdout.isTTY ? `\x1b[1m${text}\x1b[0m` : String(text);
}

/**
 * Formats a large token count as a short human string.
 * Args: value (number|null)
 * Returns: "12.4M" style string, or "—"
 */
function shortNumber(value) {
  if (value == null || !Number.isFinite(value)) {
    return "—";
  }
  if (value >= 1e9) {
    return `${(value / 1e9).toFixed(1)}B`;
  }
  if (value >= 1e6) {
    return `${(value / 1e6).toFixed(1)}M`;
  }
  if (value >= 1e3) {
    return `${(value / 1e3).toFixed(1)}K`;
  }
  return String(Math.round(value));
}

/**
 * Formats a fractional hour count as "13h12m".
 * Args: hours (number|null)
 * Returns: string, or "—"
 */
function duration(hours) {
  if (hours == null || !Number.isFinite(hours)) {
    return "—";
  }
  const whole = Math.floor(hours);
  return `${whole}h${String(Math.round((hours - whole) * 60)).padStart(2, "0")}m`;
}

/**
 * Picks the one action worth taking, from the weakest component.
 * Args: day (dayRecord), config (object)
 * Returns: {action, guardrail, mood}
 * Handles: a day off (rest is the action), every component missing
 */
function advise(day, config) {
  if (day.day_off) {
    return { action: "Day off — nothing to fix.", guardrail: "Start tomorrow no earlier than 09:00.", mood: "rest" };
  }
  const entries = Object.entries(day.components).filter(([, value]) => value != null);
  if (!entries.length) {
    return { action: "Not enough signal to advise yet.", guardrail: "Let the history build for a week.", mood: "momentum" };
  }
  const [weakest] = entries.sort((a, b) => a[1] - b[1]);
  const stop = `${config.stopBy || "21:00"}`;
  switch (weakest[0]) {
    case "dayLength":
      return {
        action: `Day length is the weakest link — ${duration(day.work_hours)} from ${clock(day.first_ts, config)}.`,
        guardrail: `Tomorrow: stop at ${stop}, whatever is open.`,
        mood: "stop",
      };
    case "sleep":
      return {
        action:
          day.sleep_minutes == null
            ? `Last activity ${clock(day.last_ts, config)} — the night is being eaten from the front.`
            : `${duration(day.sleep_minutes / 60)} asleep, short of 7h30m.`,
        guardrail: `Tonight: last commit by ${stop}, lights out by 23:00.`,
        mood: "rest",
      };
    case "intensity":
      return {
        action: `Volume is ${day.token_ratio ? `${day.token_ratio.toFixed(1)}×` : "well above"} your 28-day normal.`,
        guardrail: "Tomorrow: one repo, one task, no parallel sessions.",
        mood: "focus",
      };
    default:
      return {
        action: `${day.days_off_last_7} day${day.days_off_last_7 === 1 ? "" : "s"} off in the last 7.`,
        guardrail: "This week: book one full day with zero commits.",
        mood: "rest",
      };
  }
}

/**
 * Reads the record of which quotes have been shown and when.
 * Args: none
 * Returns: object mapping quote id to the date it was last shown, plus `last_shown`
 * Handles: no file yet, a corrupt file (both give an empty record)
 */
function readSeen() {
  try {
    return JSON.parse(fs.readFileSync(SEEN_FILE, "utf8"));
  } catch (error) {
    return {};
  }
}

/**
 * Decides whether a motivational line is warranted at all — it almost never is.
 * A quote only earns its place on a day that was genuinely hard, never twice inside a few
 * days, and then only one time in twenty, so it stays a surprise rather than wallpaper.
 * Args: day (dayRecord), date (string "YYYY-MM-DD"), force (boolean) — bypasses the gate,
 *       seen (object) — the shown-record, read from disk when not supplied
 * Returns: boolean
 * Handles: a day that was never scored, a missing or corrupt seen-file, the caller
 *          asking twice in a row (the gap check stops a cluster)
 */
function quoteWarranted(day, date, force, seen = readSeen()) {
  if (force) {
    return true;
  }
  if (day.score == null || day.score >= QUOTE_SCORE_CEILING) {
    return false;
  }
  if (seen.last_shown && seen.last_shown > shiftKey(date, -QUOTE_GAP_DAYS)) {
    return false;
  }
  return Math.random() < QUOTE_RATE;
}

/**
 * Picks the one line worth reading, chosen for how the day actually went rather than at random.
 * Args: mood (string) — from advise(); band (string) — today's band; date (string "YYYY-MM-DD")
 * Returns: {id, text, author} or null when the bank cannot be read
 * Handles: a missing or corrupt quotes file, a bank exhausted by the cooldown (it resets),
 *          two runs on the same day (the same quote both times, never a reshuffle)
 */
function pickQuote(mood, band, date) {
  let bank = [];
  try {
    bank = JSON.parse(fs.readFileSync(QUOTES_FILE, "utf8"));
  } catch (error) {
    return null;
  }
  if (!Array.isArray(bank) || !bank.length) {
    return null;
  }
  const seen = readSeen();
  const cutoff = shiftKey(date, -QUOTE_COOLDOWN_DAYS);
  const fresh = (quote) => !seen[quote.id] || seen[quote.id] < cutoff || seen[quote.id] === date;
  const bankIds = new Set(bank.map((quote) => quote.id));
  for (const key of Object.keys(seen)) {
    if (key !== "last_shown" && !bankIds.has(key)) {
      delete seen[key];
    }
  }
  const wanted = [mood, band === "Burnout risk" ? "comeback" : band === "Balanced" ? "balanced" : "momentum"];

  let pool = bank.filter((quote) => fresh(quote) && quote.moods.some((tag) => wanted.includes(tag)));
  if (!pool.length) {
    pool = bank.filter(fresh);
  }
  if (!pool.length) {
    pool = bank;
  }
  let hash = 0;
  for (const character of date) {
    hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
  }
  const chosen = pool[hash % pool.length];
  seen[chosen.id] = date;
  seen.last_shown = date;
  try {
    fs.mkdirSync(DIR, { recursive: true });
    fs.writeFileSync(SEEN_FILE, JSON.stringify(seen));
  } catch (error) {
    return chosen;
  }
  return chosen;
}

/**
 * Formats a "YYYY-MM-DD" key as "22 Sep" for the chart axis.
 * Args: key (string|undefined)
 * Returns: string, or "" when the key is missing or malformed
 */
function monthDay(key) {
  if (!key || !/^\d{4}-\d{2}-\d{2}$/.test(key)) {
    return "";
  }
  return `${Number(key.slice(8))} ${MONTHS[Number(key.slice(5, 7)) - 1]}`;
}

/**
 * Prints the whole report: one block per idea, a blank line between blocks, and every
 * value in the same column so the eye can run down it.
 * Args: days (dayRecord[] oldest first), config (object), sourcesUsed (string[]), sourcesMissing (string[])
 * Returns: nothing — writes to stdout
 * Handles: a today with no activity, an empty history, every optional source missing
 */
function render(days, config, sourcesUsed, sourcesMissing) {
  const today = days[days.length - 1];
  const index = days.length - 1;
  const week = rollingAverage(days, index, 7);
  const previousWeek = rollingAverage(days, index - 7, 7);
  const trend =
    week == null || previousWeek == null
      ? ""
      : week > previousWeek + 0.1
        ? `↑ from ${previousWeek.toFixed(1)}`
        : week < previousWeek - 0.1
          ? `↓ from ${previousWeek.toFixed(1)}`
          : `level with ${previousWeek.toFixed(1)}`;

  const boundary = String(config.dayStartHour).padStart(2, "0");
  const out = [""];
  const rule = "─".repeat(66);
  out.push(`  🧘 ${bold("God Zen")}  ·  ${today.date}  ·  ${config.timezone}, day runs ${boundary}:00 → ${boundary}:00`);
  out.push(`  ${rule}`);
  out.push("");
  out.push(`  ${"Zen Score".padEnd(11)}${bold(today.score == null ? "—" : `${today.score} / 10`)}   ${bold(today.band)}`);
  out.push(`  ${"".padEnd(11)}7-day avg ${week == null ? "—" : week.toFixed(1)}${trend ? `, ${trend}` : ""}`);
  out.push("");

  const rows = [
    ["Day length", today.components.dayLength, `${duration(today.work_hours)}  ·  ${clock(today.first_ts, config)} → ${clock(today.last_ts, config)}`],
    [
      "Sleep",
      today.components.sleep,
      today.sleep_minutes == null
        ? `no Health data  ·  last activity ${clock(today.last_ts, config)}`
        : `${duration(today.sleep_minutes / 60)} asleep  ·  ${today.bedtime || "—"} → ${today.wake || "—"}`,
    ],
    [
      "Intensity",
      today.components.intensity,
      `tokens ${today.token_ratio ? `${today.token_ratio.toFixed(1)}×` : "—"}  ·  commits ${today.commit_ratio ? `${today.commit_ratio.toFixed(1)}×` : "—"}  vs your ${today.baseline.days}-day normal`,
    ],
    ["Recovery", today.components.recovery, `${today.days_off_last_7} day${today.days_off_last_7 === 1 ? "" : "s"} off in the last 7`],
  ];
  for (const [label, value, raw] of rows) {
    out.push(`  ${label.padEnd(11)}${bold((value == null ? "—" : value.toFixed(1)).padStart(4))}   ${raw}`);
  }

  const window = days.slice(-CHART_DAYS);
  out.push("");
  out.push(`  ${bold(`Last ${window.length} days`)}   score out of 10, taller is better   ┄ guides at 5 and 8   no bar = day off`);
  out.push("");
  for (const line of chart(
    window.map((day) => day.score),
    window.map((day) => day.date)
  )) {
    out.push(line);
  }

  const month = today.date.slice(0, 7);
  const monthDays = days.filter((day) => day.date.startsWith(month));
  const monthCost = monthDays.reduce((sum, day) => sum + (day.cost || 0), 0);
  const monthTokens = monthDays.reduce((sum, day) => sum + (day.tokens || 0), 0);
  const monthCommits = monthDays.reduce((sum, day) => sum + day.commits, 0);
  const elapsed = Number(today.date.slice(8));
  const inMonth = new Date(Date.UTC(Number(month.slice(0, 4)), Number(month.slice(5, 7)), 0)).getUTCDate();
  const projected = elapsed ? (monthCost / elapsed) * inMonth : null;
  const normalMonth = today.baseline.tokens ? today.baseline.tokens * inMonth : null;
  const monthRatio = normalMonth && elapsed ? ((monthTokens / elapsed) * inMonth) / normalMonth : null;
  const money = (value) => (value == null ? "—" : `$${value.toFixed(2)}`);

  out.push("");
  out.push(`  ${"Tokens".padEnd(11)}today       ${bold(shortNumber(today.tokens).padEnd(8))} ${bold(money(today.cost))}`);
  out.push(`  ${"".padEnd(11)}month       ${shortNumber(monthTokens).padEnd(8)} ${money(monthCost)}`);
  out.push(
    `  ${"".padEnd(11)}projected            ${bold(projected == null ? "—" : `$${projected.toFixed(0)}`)}${monthRatio ? `  ·  ${monthRatio.toFixed(1)}× a normal month` : ""}  ·  ${monthCommits ? money(monthCost / monthCommits) : "—"} per commit`
  );

  let streak = 0;
  for (let back = days.length - 1; back >= 0 && !days[back].day_off; back -= 1) {
    streak += 1;
  }
  const lastOff = days.filter((day) => day.day_off).pop();
  const fortnight = days.slice(-14).filter((day) => !day.day_off);
  const late = fortnight.filter((day) => day.last_activity_hours >= 23 - config.dayStartHour).length;
  const pastMidnight = fortnight.filter((day) => day.past_midnight).length;

  out.push("");
  out.push(
    `  ${"Pace".padEnd(11)}${bold(`${streak}-day streak`)}  ·  last day off ${bold(lastOff ? monthDay(lastOff.date) : `none in ${days.length} days`)}`
  );
  out.push(`  ${"".padEnd(11)}last 14 days: ${bold(late)} night${late === 1 ? "" : "s"} past 23:00  ·  ${bold(pastMidnight)} past midnight`);
  out.push("");
  out.push(
    `  ${"Focus".padEnd(11)}${bold(`${today.repos.length} repo${today.repos.length === 1 ? "" : "s"}`)}${today.repos.length ? `: ${today.repos.slice(0, 4).join(", ")}` : ""}`
  );
  out.push(
    `  ${"".padEnd(11)}${bold(today.max_parallel_sessions)} parallel session${today.max_parallel_sessions === 1 ? "" : "s"}  ·  ${today.meeting_minutes ? `${duration(today.meeting_minutes / 60)} of meetings` : "no meetings"}`
  );

  const { action, guardrail } = advise(today, config);
  out.push("");
  out.push(`  ${bold("Do this".padEnd(11))}${action}`);
  out.push(`  ${"".padEnd(11)}${guardrail}`);
  out.push("");
  out.push(`  ${rule}`);
  out.push(`  ${"sources".padEnd(11)}${sourcesUsed.join("  ·  ") || "none"}`);
  if (sourcesMissing.length) {
    out.push(`  ${"missing".padEnd(11)}${sourcesMissing.join("  ·  ")}`);
  }
  out.push("");
  process.stdout.write(`${out.join("\n")}\n`);
}

/**
 * Parses the command line.
 * Args: argv (string[])
 * Returns: {mcp, date, json, rebuild, quote, force}
 * Handles: --mcp-file pointing nowhere, flags in any order, unknown flags (ignored),
 *          a --date that is not a real YYYY-MM-DD (dropped, so today is used)
 */
function parseArgs(argv) {
  const args = { mcp: null, date: null, json: false, rebuild: false, quote: false, force: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === "--mcp") {
      args.mcp = argv[++index] || null;
    } else if (flag === "--mcp-file") {
      const file = argv[++index];
      try {
        args.mcp = fs.readFileSync(expandHome(file), "utf8");
      } catch (error) {
        args.mcp = null;
      }
    } else if (flag === "--date") {
      const value = argv[++index] || "";
      args.date = /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) ? value : null;
    } else if (flag === "--json") {
      args.json = true;
    } else if (flag === "--quote") {
      args.quote = true;
    } else if (flag === "--force") {
      args.force = true;
    } else if (flag === "--rebuild") {
      args.rebuild = true;
    }
  }
  return args;
}

/**
 * Collects every source, updates the history and prints the report.
 * Args: argv (string[])
 * Returns: nothing
 * Handles: the first run (30 days are backfilled), later runs (only today is recollected),
 *          every source being unavailable — the report still prints and names what is missing
 */
function main(argv) {
  const args = parseArgs(argv);
  const config = loadConfig();
  const now = Date.now();
  const today = args.date || dayKey(now, config);
  const history = readHistory();
  const keys = [];
  for (let back = HISTORY_DAYS - 1; back >= 0; back -= 1) {
    keys.push(shiftKey(today, -back));
  }
  if (args.quote) {
    const known = scoreDays(keys.map((key) => history.get(key) || blankDay(key)), config);
    const latest = known[known.length - 1];
    if (!quoteWarranted(latest, latest.date, args.force)) {
      return;
    }
    const line = pickQuote(advise(latest, config).mood, latest.band, latest.date);
    if (line) {
      process.stdout.write(`🧘 "${line.text}" — ${line.author}\n`);
    }
    return;
  }
  const firstRun = args.rebuild || !keys.slice(0, -1).every((key) => history.has(key));
  const rebuildKeys = firstRun ? keys : [today];
  const sinceEpoch = Date.parse(`${rebuildKeys[0]}T00:00:00Z`) - DAY_MS;

  const repos = findRepos(config.repoRoots, config.maxDepth);
  const commits = collectGit(repos, config.authorEmails, sinceEpoch);
  const ccusage = collectCcusage(sinceEpoch, config.useCcusage);
  const claude = collectClaudeLogs(sinceEpoch, !ccusage.ok);
  const sleep = collectSleep(config.healthFolder);
  const hookActivity = collectHookActivity(sinceEpoch);
  const mcp = parseMcp(args.mcp);

  const rebuilt = buildDays({ commits, ccusage, claude, sleep, hookActivity, mcp }, config, rebuildKeys);
  for (const [key, day] of Object.entries(rebuilt)) {
    history.set(key, day);
  }
  const days = keys.map((key) => history.get(key) || blankDay(key));
  writeHistory([...history.values()], today);
  scoreDays(days, config);

  const used = [];
  const missing = [];
  (commits.length ? used : missing).push(`git (${repos.length} repos)`);
  (ccusage.ok ? used : missing).push("ccusage");
  (claude.ok ? used : missing).push("claude logs");
  (Object.keys(sleep).length ? used : missing).push("apple health sleep");
  (hookActivity.length ? used : missing).push("zen hook");
  if (mcp.sources.length) {
    used.push(...mcp.sources);
  } else {
    missing.push("mcp tools");
  }

  if (args.json) {
    process.stdout.write(`${JSON.stringify({ today: days[days.length - 1], days, sources: { used, missing } }, null, 2)}\n`);
    return;
  }
  render(days, config, used, missing);
}

if (require.main === module) {
  main(process.argv.slice(2));
}

module.exports = {
  main,
  parseArgs,
  parseMcp,
  dayKey,
  hoursFromDayStart,
  shiftKey,
  buildDays,
  scoreDays,
  maxParallelSessions,
  chart,
  duration,
  shortNumber,
  monthDay,
  advise,
  collectSleep,
  findRepos,
  pickQuote,
  quoteWarranted,
  blankDay,
  DEFAULT_CONFIG,
};
