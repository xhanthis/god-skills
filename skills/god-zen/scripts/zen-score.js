"use strict";

/**
 * Pure scoring for the God Zen daily report.
 * No clock, no filesystem, no config lookups — every function takes numbers and returns
 * numbers so the suite can pin the algorithm without a machine to run it on.
 * Every component is 0–10; the weighted blend is the Zen Score.
 */

const WEIGHTS = { dayLength: 0.35, sleep: 0.3, intensity: 0.2, recovery: 0.15 };
const EASY_DAY_HOURS = 8;
const CUTOFF_HOUR = 21;
const GOOD_SLEEP_HOURS = 7.5;
const SHORT_SLEEP_HOURS = 5;
const TOKEN_WEIGHT = 0.6;
const COMMIT_WEIGHT = 0.4;
const BANDS = [
  { min: 8, label: "Balanced" },
  { min: 5, label: "Stretched" },
  { min: -Infinity, label: "Burnout risk" },
];

/**
 * Keeps a number inside an inclusive range.
 * Args: value (number), low (number), high (number)
 * Returns: number within [low, high]
 * Handles: NaN and non-finite input by returning low
 */
function clamp(value, low = 0, high = 10) {
  if (!Number.isFinite(value)) {
    return low;
  }
  return Math.min(high, Math.max(low, value));
}

/**
 * Median of a list of numbers.
 * Args: values (number[])
 * Returns: number, or null when the list is empty
 * Handles: even-length lists (mean of the middle pair), unsorted input, non-finite entries
 */
function median(values) {
  const sorted = (values || []).filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) {
    return null;
  }
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * Scores the length of the work window: a day of 8 hours or less is perfect.
 * Args: hours (number) — earliest to latest activity across every source
 * Returns: 0–10, losing 2 points per hour beyond 8
 * Handles: null hours (a day with no activity) by returning null
 */
function dayLengthScore(hours) {
  if (hours == null) {
    return null;
  }
  return clamp(10 - 2 * Math.max(0, hours - EASY_DAY_HOURS));
}

/**
 * Scores how long the night before the workday was.
 * Args: hours (number) — minutes asleep, as hours
 * Returns: 0–10, losing 3 points per hour under 7.5
 * Handles: null hours (no Apple Health data) by returning null
 */
function sleepDurationScore(hours) {
  if (hours == null) {
    return null;
  }
  return clamp(10 - 3 * Math.max(0, GOOD_SLEEP_HOURS - hours));
}

/**
 * Scores how late the day's last activity was.
 * Args: hoursFromDayStart (number) — hours since the day boundary, dayStartHour (number)
 * Returns: 0–10; stopping by 21:00 is 10, each later hour costs 2, anything past midnight is 0
 * Handles: null input by returning null; a day boundary other than 05:00
 */
function cutoffScore(hoursFromDayStart, dayStartHour = 5) {
  if (hoursFromDayStart == null) {
    return null;
  }
  const cutoff = CUTOFF_HOUR - dayStartHour;
  const midnight = 24 - dayStartHour;
  if (hoursFromDayStart >= midnight) {
    return 0;
  }
  return clamp(10 - 2 * Math.max(0, hoursFromDayStart - cutoff));
}

/**
 * Blends sleep duration and the stop-work cutoff into one rest score.
 * Args: asleepMinutes (number|null), lastActivityHours (number|null), dayStartHour (number)
 * Returns: 0–10 — the average of both halves, or the cutoff alone when Health data is missing
 * Handles: no Health data, no activity at all (returns null)
 */
function sleepScore({ asleepMinutes = null, lastActivityHours = null, dayStartHour = 5 } = {}) {
  const cutoff = cutoffScore(lastActivityHours, dayStartHour);
  const duration = sleepDurationScore(asleepMinutes == null ? null : asleepMinutes / 60);
  if (duration == null) {
    return cutoff;
  }
  if (cutoff == null) {
    return duration;
  }
  return (duration + cutoff) / 2;
}

/**
 * Scores today's volume against the user's own normal.
 * Args: ratio (number) — today divided by the 28-day active-day median
 * Returns: 0–10; at or below normal is 10, then 3 points per doubling
 * Handles: null or non-positive baseline (returns null), a zero-activity today (ratio 0 → 10)
 */
function ratioScore(ratio) {
  if (ratio == null || !Number.isFinite(ratio)) {
    return null;
  }
  if (ratio <= 1) {
    return 10;
  }
  return clamp(10 - 3 * Math.log2(ratio));
}

/**
 * Weighted intensity across tokens burned and commits landed.
 * Args: tokenRatio (number|null), commitRatio (number|null)
 * Returns: 0–10 (tokens 60%, commits 40%), or null when neither baseline exists
 * Handles: one missing baseline by scoring on the other alone
 */
function intensityScore({ tokenRatio = null, commitRatio = null } = {}) {
  const tokens = ratioScore(tokenRatio);
  const commits = ratioScore(commitRatio);
  if (tokens == null && commits == null) {
    return null;
  }
  if (tokens == null) {
    return commits;
  }
  if (commits == null) {
    return tokens;
  }
  return tokens * TOKEN_WEIGHT + commits * COMMIT_WEIGHT;
}

/**
 * Scores rest days taken in the last seven, today included.
 * Args: daysOff (number)
 * Returns: 10 for two or more, 6 for one, 2 for none
 * Handles: null input by returning null
 */
function recoveryScore(daysOff) {
  if (daysOff == null) {
    return null;
  }
  if (daysOff >= 2) {
    return 10;
  }
  return daysOff === 1 ? 6 : 2;
}

/**
 * Blends the four components into the Zen Score.
 * Args: components ({dayLength, sleep, intensity, recovery}), flags ({pastMidnight, sleepHours})
 * Returns: 0–10 rounded to one decimal, or null when no component could be scored
 * Handles: missing components (their weight is redistributed), the hard caps for
 *          any activity past midnight or a night under five hours (score cannot exceed 5)
 */
function zenScore(components = {}, flags = {}) {
  let total = 0;
  let weight = 0;
  for (const [key, share] of Object.entries(WEIGHTS)) {
    const value = components[key];
    if (value == null) {
      continue;
    }
    total += clamp(value) * share;
    weight += share;
  }
  if (weight === 0) {
    return null;
  }
  let score = total / weight;
  const shortNight = flags.sleepHours != null && flags.sleepHours < SHORT_SLEEP_HOURS;
  if (flags.pastMidnight || shortNight) {
    score = Math.min(score, 5);
  }
  return Math.round(score * 10) / 10;
}

/**
 * Names the band a score falls in.
 * Args: score (number|null)
 * Returns: "Balanced" | "Stretched" | "Burnout risk", or "Day off" for a null score
 */
function band(score) {
  if (score == null) {
    return "Day off";
  }
  return BANDS.find((entry) => score >= entry.min).label;
}

module.exports = {
  WEIGHTS,
  SHORT_SLEEP_HOURS,
  clamp,
  median,
  dayLengthScore,
  sleepDurationScore,
  cutoffScore,
  sleepScore,
  ratioScore,
  intensityScore,
  recoveryScore,
  zenScore,
  band,
};
