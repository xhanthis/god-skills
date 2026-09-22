"use strict";

/**
 * Suite for the God Zen daily report. Zero dependencies — node:test only, like the rest
 * of this repo's tooling. Every case is Arrange / Act / Assert.
 * Run: node --test skills/god-zen/scripts/
 */

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const score = require("./zen-score");
const report = require("./zen-report");

const CONFIG = { timezone: "Asia/Kolkata", dayStartHour: 5 };

/**
 * Builds an epoch for a wall-clock time in Asia/Kolkata (UTC+05:30, no DST).
 * Args: date (string "YYYY-MM-DD"), hhmm (string "HH:MM")
 * Returns: epoch milliseconds
 */
function ist(date, hhmm) {
  return Date.parse(`${date}T${hhmm}:00+05:30`);
}

test("clamp keeps a value inside the range", () => {
  assert.equal(score.clamp(12), 10);
  assert.equal(score.clamp(-3), 0);
  assert.equal(score.clamp(NaN), 0);
  assert.equal(score.clamp(4.5), 4.5);
});

test("median handles odd, even and empty lists", () => {
  assert.equal(score.median([3, 1, 2]), 2);
  assert.equal(score.median([4, 1, 3, 2]), 2.5);
  assert.equal(score.median([]), null);
});

test("day length scores 10 up to eight hours then loses two an hour", () => {
  // Arrange / Act / Assert
  assert.equal(score.dayLengthScore(6), 10);
  assert.equal(score.dayLengthScore(8), 10);
  assert.equal(score.dayLengthScore(9), 8);
  assert.equal(score.dayLengthScore(13), 0);
  assert.equal(score.dayLengthScore(20), 0);
  assert.equal(score.dayLengthScore(null), null);
});

test("sleep duration scores 10 at 7h30m then loses three an hour", () => {
  assert.equal(score.sleepDurationScore(8), 10);
  assert.equal(score.sleepDurationScore(7.5), 10);
  assert.equal(score.sleepDurationScore(6.5), 7);
  assert.equal(score.sleepDurationScore(4), 0);
  assert.equal(score.sleepDurationScore(null), null);
});

test("cutoff scores 10 at 21:00, 6 at 23:00 and 0 past midnight", () => {
  // Arrange: hours are measured from the 05:00 day boundary
  const ninePm = 16;
  const elevenPm = 18;
  const halfPastMidnight = 19.48;

  // Act / Assert
  assert.equal(score.cutoffScore(ninePm), 10);
  assert.equal(score.cutoffScore(elevenPm), 6);
  assert.equal(score.cutoffScore(halfPastMidnight), 0);
  assert.equal(score.cutoffScore(12), 10);
  assert.equal(score.cutoffScore(null), null);
});

test("sleep falls back to the cutoff alone when Health data is missing", () => {
  // Arrange
  const withoutHealth = { asleepMinutes: null, lastActivityHours: 18, dayStartHour: 5 };
  const withHealth = { asleepMinutes: 6.5 * 60, lastActivityHours: 18, dayStartHour: 5 };

  // Act / Assert
  assert.equal(score.sleepScore(withoutHealth), 6);
  assert.equal(score.sleepScore(withHealth), (7 + 6) / 2);
});

test("ratio scores 10 at or under normal and loses three a doubling", () => {
  assert.equal(score.ratioScore(0.4), 10);
  assert.equal(score.ratioScore(1), 10);
  assert.equal(score.ratioScore(2), 7);
  assert.equal(score.ratioScore(4), 4);
  assert.equal(score.ratioScore(10.4), 0);
  assert.equal(score.ratioScore(null), null);
});

test("intensity weighs tokens 60% and commits 40%", () => {
  // Arrange: normal tokens, four times the usual commits
  const components = { tokenRatio: 1, commitRatio: 4 };

  // Act
  const result = score.intensityScore(components);

  // Assert
  assert.equal(result, 10 * 0.6 + 4 * 0.4);
  assert.equal(score.intensityScore({ tokenRatio: null, commitRatio: 2 }), 7);
  assert.equal(score.intensityScore({}), null);
});

test("recovery rewards two days off in the last seven", () => {
  assert.equal(score.recoveryScore(3), 10);
  assert.equal(score.recoveryScore(2), 10);
  assert.equal(score.recoveryScore(1), 6);
  assert.equal(score.recoveryScore(0), 2);
  assert.equal(score.recoveryScore(null), null);
});

test("the worked example scores exactly 3.3", () => {
  // Arrange: a 13h day ending 23:00, no Health data, 10.4x tokens, 10.5x commits, 2 days off
  const components = {
    dayLength: score.dayLengthScore(13),
    sleep: score.sleepScore({ asleepMinutes: null, lastActivityHours: 18, dayStartHour: 5 }),
    intensity: score.intensityScore({ tokenRatio: 10.4, commitRatio: 10.5 }),
    recovery: score.recoveryScore(2),
  };

  // Act
  const result = score.zenScore(components, { pastMidnight: false, sleepHours: null });

  // Assert
  assert.deepEqual(components, { dayLength: 0, sleep: 6, intensity: 0, recovery: 10 });
  assert.equal(result, 3.3);
  assert.equal(score.band(result), "Burnout risk");
});

test("any activity past midnight caps the score at 5", () => {
  // Arrange: an otherwise excellent day that ran past midnight
  const components = { dayLength: 10, sleep: 10, intensity: 10, recovery: 10 };

  // Act
  const capped = score.zenScore(components, { pastMidnight: true });

  // Assert
  assert.equal(score.zenScore(components, { pastMidnight: false }), 10);
  assert.equal(capped, 5);
});

test("a night under five hours caps the score at 5", () => {
  const components = { dayLength: 10, sleep: 8, intensity: 10, recovery: 10 };
  assert.equal(score.zenScore(components, { sleepHours: 4.5 }), 5);
  assert.equal(score.zenScore(components, { sleepHours: 5 }), 9.4);
});

test("a missing component has its weight redistributed", () => {
  // Arrange: no baseline yet, so intensity cannot be scored
  const components = { dayLength: 10, sleep: 10, intensity: null, recovery: 10 };

  // Act
  const result = score.zenScore(components, {});

  // Assert
  assert.equal(result, 10);
  assert.equal(score.zenScore({}, {}), null);
});

test("bands split at 8 and 5", () => {
  assert.equal(score.band(9.9), "Balanced");
  assert.equal(score.band(8), "Balanced");
  assert.equal(score.band(7.9), "Stretched");
  assert.equal(score.band(5), "Stretched");
  assert.equal(score.band(4.9), "Burnout risk");
  assert.equal(score.band(null), "Day off");
});

test("00:29 belongs to the previous Zen day", () => {
  // Arrange
  const lateNight = ist("2026-09-23", "00:29");
  const morning = ist("2026-09-23", "09:00");

  // Act / Assert
  assert.equal(report.dayKey(lateNight, CONFIG), "2026-09-22");
  assert.equal(report.dayKey(morning, CONFIG), "2026-09-23");
  assert.equal(report.dayKey(ist("2026-09-23", "04:59"), CONFIG), "2026-09-22");
  assert.equal(report.dayKey(ist("2026-09-23", "05:00"), CONFIG), "2026-09-23");
});

test("hours from the day start wrap past midnight", () => {
  assert.equal(report.hoursFromDayStart(ist("2026-09-22", "05:00"), CONFIG), 0);
  assert.equal(report.hoursFromDayStart(ist("2026-09-22", "21:00"), CONFIG), 16);
  assert.equal(report.hoursFromDayStart(ist("2026-09-23", "00:29"), CONFIG).toFixed(2), "19.48");
});

test("shiftKey crosses months and years", () => {
  assert.equal(report.shiftKey("2026-03-01", -1), "2026-02-28");
  assert.equal(report.shiftKey("2026-01-01", -1), "2025-12-31");
  assert.equal(report.shiftKey("2026-09-22", -29), "2026-08-24");
});

test("max parallel sessions counts overlapping windows", () => {
  // Arrange: two sessions overlap, a third starts after both close
  const events = [
    { session: "a", ts: ist("2026-09-22", "10:00") },
    { session: "a", ts: ist("2026-09-22", "12:00") },
    { session: "b", ts: ist("2026-09-22", "11:00") },
    { session: "b", ts: ist("2026-09-22", "11:30") },
    { session: "c", ts: ist("2026-09-22", "18:00") },
  ];

  // Act
  const peak = report.maxParallelSessions(events);

  // Assert
  assert.equal(peak, 2);
  assert.equal(report.maxParallelSessions([]), 0);
});

test("a day with no activity anywhere is a day off", () => {
  // Arrange
  const sources = {
    commits: [],
    ccusage: { days: {}, ok: false },
    claude: { events: [], tokenStamps: [], ok: false },
    sleep: {},
    hookActivity: [],
    mcp: { timestamps: [], meetings: [], sources: [] },
  };

  // Act
  const days = report.buildDays(sources, CONFIG, ["2026-09-22"]);

  // Assert
  assert.equal(days["2026-09-22"].day_off, true);
  assert.equal(days["2026-09-22"].first_ts, null);
});

test("commits, sessions and meetings fold into one day record", () => {
  // Arrange
  const sources = {
    commits: [
      { ts: ist("2026-09-22", "09:30"), repo: "api" },
      { ts: ist("2026-09-22", "18:00"), repo: "web" },
      { ts: ist("2026-09-23", "00:29"), repo: "api" },
    ],
    ccusage: { days: { "2026-09-22": { tokens: 4000, cost: 12.5 } }, ok: true },
    claude: {
      events: [
        { ts: ist("2026-09-22", "09:00"), session: "s1", cwd: "api" },
        { ts: ist("2026-09-22", "20:00"), session: "s2", cwd: "web" },
      ],
      tokenStamps: [],
      ok: true,
    },
    sleep: { "2026-09-22": { asleepMinutes: 380, bedtime: "01:10", wake: "07:30" } },
    hookActivity: [],
    mcp: {
      timestamps: [],
      meetings: [{ start: ist("2026-09-22", "15:00"), end: ist("2026-09-22", "16:30") }],
      sources: ["google_calendar"],
    },
  };

  // Act
  const day = report.buildDays(sources, CONFIG, ["2026-09-22"])["2026-09-22"];

  // Assert
  assert.equal(day.day_off, false);
  assert.equal(day.commits, 3);
  assert.deepEqual(day.repos, ["api", "web"]);
  assert.equal(day.tokens, 4000);
  assert.equal(day.cost, 12.5);
  assert.equal(day.sessions, 2);
  assert.equal(day.sleep_minutes, 380);
  assert.equal(day.meeting_minutes, 90);
  assert.equal(day.first_ts, ist("2026-09-22", "09:00"));
  assert.equal(day.last_ts, ist("2026-09-23", "00:29"));
});

test("a 00:29 finish caps the scored day at 5", () => {
  // Arrange: a short, light day that happens to end after midnight
  const days = [
    { date: "2026-09-21", day_off: true, commits: 0, tokens: 0, repos: [], first_ts: null, last_ts: null },
    {
      date: "2026-09-22",
      day_off: false,
      commits: 1,
      tokens: 100,
      repos: ["api"],
      first_ts: ist("2026-09-22", "22:00"),
      last_ts: ist("2026-09-23", "00:29"),
      sleep_minutes: null,
    },
  ];

  // Act
  const scored = report.scoreDays(days, CONFIG);
  const today = scored[1];

  // Assert
  assert.equal(today.past_midnight, true);
  assert.equal(today.components.dayLength, 10);
  assert.equal(today.components.sleep, 0);
  assert.ok(today.score <= 5, `expected a capped score, got ${today.score}`);
});

test("scoring survives a history with no baseline at all", () => {
  // Arrange
  const days = [
    {
      date: "2026-09-22",
      day_off: false,
      commits: 4,
      tokens: 1000,
      repos: ["api"],
      first_ts: ist("2026-09-22", "10:00"),
      last_ts: ist("2026-09-22", "17:00"),
      sleep_minutes: null,
    },
  ];

  // Act
  const today = report.scoreDays(days, CONFIG)[0];

  // Assert
  assert.equal(today.components.intensity, null);
  assert.equal(today.baseline.days, 0);
  assert.equal(today.components.recovery, 2);
  assert.equal(today.score, 8.5);
});

test("a --date that is not a real date is dropped rather than crashing", () => {
  // Arrange / Act
  const garbage = report.parseArgs(["--date", "foo"]);
  const missing = report.parseArgs(["--date"]);
  const impossible = report.parseArgs(["--date", "2026-13-45"]);
  const good = report.parseArgs(["--date", "2026-09-22"]);

  // Assert
  assert.equal(garbage.date, null);
  assert.equal(missing.date, null);
  assert.equal(impossible.date, null);
  assert.equal(good.date, "2026-09-22");
});

test("history is staged and renamed so a crash cannot tear it", () => {
  // Arrange
  const source = fs.readFileSync(path.join(__dirname, "zen-report.js"), "utf8");

  // Assert
  assert.match(source, /renameSync\(temp, HISTORY_FILE\)/);
  assert.match(source, /stat\.size > MAX_LOG_BYTES/);
});

test("a bad or absent MCP payload never throws", () => {
  assert.deepEqual(report.parseMcp(null), { timestamps: [], meetings: [], sources: [] });
  assert.deepEqual(report.parseMcp("not json"), { timestamps: [], meetings: [], sources: [] });
  const parsed = report.parseMcp(JSON.stringify({ timestamps: ["2026-09-22T10:00:00+05:30", "nope"], sources: ["slack"] }));
  assert.equal(parsed.timestamps.length, 1);
  assert.deepEqual(parsed.sources, ["slack"]);
});

test("a missing Health folder yields no nights rather than an error", () => {
  assert.deepEqual(report.collectSleep("/tmp/god-zen-does-not-exist-12345"), {});
});

test("repos are discovered under the configured roots", () => {
  // Arrange
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "zen-repos-"));
  fs.mkdirSync(path.join(root, "one", ".git"), { recursive: true });
  fs.mkdirSync(path.join(root, "nested", "two", ".git"), { recursive: true });
  fs.mkdirSync(path.join(root, "node_modules", "pkg", ".git"), { recursive: true });

  // Act
  const found = report.findRepos([root], 3).map((dir) => path.basename(dir)).sort();

  // Assert
  assert.deepEqual(found, ["one", "two"]);
  fs.rmSync(root, { recursive: true, force: true });
});

test("formatters stay readable with missing values", () => {
  assert.equal(report.duration(13.2), "13h12m");
  assert.equal(report.duration(null), "—");
  assert.equal(report.shortNumber(47660155), "47.7M");
  assert.equal(report.shortNumber(null), "—");
});

test("the advice names the weakest component", () => {
  // Arrange
  const day = {
    day_off: false,
    components: { dayLength: 0, sleep: 6, intensity: 4, recovery: 10 },
    work_hours: 13,
    first_ts: ist("2026-09-22", "09:00"),
    last_ts: ist("2026-09-22", "22:00"),
    days_off_last_7: 2,
    sleep_minutes: null,
  };

  // Act
  const advice = report.advise(day, CONFIG);

  // Assert
  assert.match(advice.action, /Day length/);
  assert.match(advice.guardrail, /21:00/);
});

test("the chart falls back to the built-in grid without asciichart", () => {
  // Arrange
  const daily = [3, null, 7, 9];

  // Act
  const lines = report.chart(daily, [3, 3, 5, 6]);

  // Assert
  assert.ok(lines.length >= 4);
  assert.ok(lines.join("\n").length > 0);
  assert.deepEqual(report.chart([5], [5]), ["  not enough history yet"]);
});

test("the report runs end to end with every source missing", () => {
  // Arrange: an empty HOME, so there is no git, no Claude log, no Health folder
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "zen-home-"));
  fs.mkdirSync(path.join(home, ".god-zen"));
  fs.writeFileSync(
    path.join(home, ".god-zen", "config.json"),
    JSON.stringify({ ...report.DEFAULT_CONFIG, repoRoots: [path.join(home, "empty")], authorEmails: ["nobody@example.invalid"], useCcusage: false })
  );

  // Act
  const output = execFileSync(process.execPath, [path.join(__dirname, "zen-report.js")], {
    encoding: "utf8",
    env: { ...process.env, HOME: home },
    timeout: 60000,
  });

  // Assert
  assert.match(output, /God Zen/);
  assert.match(output, /missing: /);
  assert.match(output, /ccusage/);
  assert.ok(fs.existsSync(path.join(home, ".god-zen", "history.jsonl")), "history is written on the first run");
  fs.rmSync(home, { recursive: true, force: true });
});
