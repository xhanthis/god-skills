#!/usr/bin/env node
/**
 * God Skills installer.
 *
 * Copies skill folders from this package into a Claude Code skills directory.
 * Zero dependencies — Node built-ins only.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");

const SOURCE_DIR = path.join(__dirname, "..", "skills");
const GLOBAL_TARGET = path.join(os.homedir(), ".claude", "skills");
const PROJECT_TARGET = path.join(process.cwd(), ".claude", "skills");

const COLORS = {
  reset: "\u001b[0m",
  bold: "\u001b[1m",
  dim: "\u001b[2m",
  green: "\u001b[32m",
  yellow: "\u001b[33m",
  red: "\u001b[31m",
  cyan: "\u001b[36m"
};

/** Wraps text in an ANSI colour unless output is being piped. */
function paint(text, color) {
  if (!process.stdout.isTTY) {
    return text;
  }
  return `${COLORS[color]}${text}${COLORS.reset}`;
}

/** Returns every skill folder name shipped in this package, sorted. */
function availableSkills() {
  if (!fs.existsSync(SOURCE_DIR)) {
    return [];
  }
  return fs
    .readdirSync(SOURCE_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => fs.existsSync(path.join(SOURCE_DIR, entry.name, "SKILL.md")))
    .map((entry) => entry.name)
    .sort();
}

/** Reads the description line from a skill's YAML frontmatter. */
function describeSkill(name) {
  const file = path.join(SOURCE_DIR, name, "SKILL.md");
  const text = fs.readFileSync(file, "utf8");
  const match = text.match(/^description:\s*(.+)$/m);
  if (!match) {
    return "";
  }
  const sentence = match[1].split(". ")[0];
  return sentence.length > 92 ? `${sentence.slice(0, 89)}...` : sentence;
}

/** Parses argv into a normalised options object. */
function parseArgs(argv) {
  const options = {
    command: "install",
    skills: [],
    scope: null,
    force: false,
    yes: false,
    help: false
  };

  for (const arg of argv) {
    if (arg === "list" || arg === "install") {
      options.command = arg;
    } else if (arg === "--global" || arg === "-g") {
      options.scope = "global";
    } else if (arg === "--project" || arg === "-p") {
      options.scope = "project";
    } else if (arg === "--force" || arg === "-f") {
      options.force = true;
    } else if (arg === "--yes" || arg === "-y") {
      options.yes = true;
    } else if (arg === "--all" || arg === "-a") {
      options.skills = [];
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (!arg.startsWith("-")) {
      options.skills.push(arg);
    }
  }

  return options;
}

/** Prints usage and exits. */
function printHelp() {
  const lines = [
    "",
    paint("God Skills", "bold") + " — Claude Code agent skills installer",
    "",
    paint("Usage", "bold"),
    "  npx god-skills                     install every skill (asks where)",
    "  npx god-skills god-dev god-tester  install only these skills",
    "  npx god-skills list                show every available skill",
    "",
    paint("Options", "bold"),
    "  -g, --global    install to ~/.claude/skills (all projects)",
    "  -p, --project   install to ./.claude/skills (this repo)",
    "  -a, --all       install every skill",
    "  -f, --force     overwrite skills that already exist",
    "  -y, --yes       skip prompts, default to global",
    "  -h, --help      show this",
    "",
    paint("Restart Claude Code after installing — skills load at session start.", "dim"),
    ""
  ];
  console.log(lines.join("\n"));
}

/** Asks a question on stdin and resolves with the trimmed answer. */
function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

/** Copies a directory tree recursively. */
function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const src = path.join(from, entry.name);
    const dest = path.join(to, entry.name);
    if (entry.isDirectory()) {
      copyDir(src, dest);
    } else {
      fs.copyFileSync(src, dest);
    }
  }
}

/** Resolves the install directory, prompting when scope was not passed. */
async function resolveTarget(options) {
  if (options.scope === "global") {
    return GLOBAL_TARGET;
  }
  if (options.scope === "project") {
    return PROJECT_TARGET;
  }
  if (options.yes || !process.stdin.isTTY) {
    return GLOBAL_TARGET;
  }

  console.log("");
  console.log(`  ${paint("1", "cyan")}  Global   ${paint(GLOBAL_TARGET, "dim")}`);
  console.log(`  ${paint("2", "cyan")}  Project  ${paint(PROJECT_TARGET, "dim")}`);
  console.log("");
  const answer = await ask("Install where? [1] ");
  return answer === "2" ? PROJECT_TARGET : GLOBAL_TARGET;
}

/** Installs the chosen skills and prints a summary. */
async function install(options) {
  const all = availableSkills();
  if (all.length === 0) {
    console.error(paint("No skills found in this package.", "red"));
    process.exit(1);
  }

  const requested =
    options.skills.length > 0
      ? options.skills.map((name) => (all.includes(name) ? name : `god-${name}`))
      : all;
  const unknown = requested.filter((name) => !all.includes(name));
  if (unknown.length > 0) {
    console.error(paint(`Unknown skill(s): ${unknown.join(", ")}`, "red"));
    console.error(paint("Run `npx god-skills list` to see what is available.", "dim"));
    process.exit(1);
  }

  const target = await resolveTarget(options);
  fs.mkdirSync(target, { recursive: true });

  const installed = [];
  const skipped = [];

  for (const name of requested) {
    const dest = path.join(target, name);
    if (fs.existsSync(dest) && !options.force) {
      skipped.push(name);
      continue;
    }
    fs.rmSync(dest, { recursive: true, force: true });
    copyDir(path.join(SOURCE_DIR, name), dest);
    installed.push(name);
  }

  console.log("");
  console.log(`${paint("✓", "green")} ${installed.length} skill(s) installed to ${paint(target, "cyan")}`);
  if (skipped.length > 0) {
    console.log(`${paint("•", "yellow")} ${skipped.length} already present, left alone: ${skipped.join(", ")}`);
    console.log(paint("  Re-run with --force to overwrite.", "dim"));
  }
  console.log("");
  console.log(paint("Restart Claude Code to load them.", "dim"));
  console.log("");
}

/** Prints every available skill with its one-line description. */
function list() {
  const all = availableSkills();
  console.log("");
  console.log(paint(`${all.length} skills available`, "bold"));
  console.log("");
  for (const name of all) {
    console.log(`  ${paint(name.padEnd(16), "cyan")} ${paint(describeSkill(name), "dim")}`);
  }
  console.log("");
  console.log(paint("Install: npx god-skills <name> [...]  or  npx god-skills --all", "dim"));
  console.log("");
}

/** Entry point. */
async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printHelp();
    return;
  }

  if (options.command === "list") {
    list();
    return;
  }

  await install(options);
}

main().catch((error) => {
  console.error(paint(`Failed: ${error.message}`, "red"));
  process.exit(1);
});
