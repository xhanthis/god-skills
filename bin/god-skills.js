#!/usr/bin/env node
/**
 * God Skills installer.
 *
 * Copies skill folders from this package into a Claude Code skills directory,
 * generates God agents from skills + agents/manifest.json (--agents), and
 * installs the hook gates (--hooks). Zero dependencies — Node built-ins only.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");

const { version } = require("../package.json");

const PACKAGE_ROOT = path.join(__dirname, "..");
const SOURCE_DIR = path.join(PACKAGE_ROOT, "skills");
const MANIFEST_FILE = path.join(PACKAGE_ROOT, "agents", "manifest.json");
const HANDOFF_FILE = path.join(PACKAGE_ROOT, "agents", "handoff.md");
const COMMANDS_DIR = path.join(PACKAGE_ROOT, "commands");
const HOOKS_SOURCE_DIR = path.join(PACKAGE_ROOT, "hooks", "god");
const SNIPPET_FILE = path.join(PACKAGE_ROOT, "hooks", "settings-snippet.json");

const GLOBAL_BASE = path.join(os.homedir(), ".claude");
const PROJECT_BASE = path.join(process.cwd(), ".claude");

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
    all: false,
    force: false,
    yes: false,
    help: false,
    version: false,
    agents: false,
    hooks: false,
    dryRun: false
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
      options.all = true;
    } else if (arg === "--agents") {
      options.agents = true;
    } else if (arg === "--hooks") {
      options.hooks = true;
    } else if (arg === "--dry-run") {
      options.dryRun = true;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--version" || arg === "-v") {
      options.version = true;
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
    "  npx god-skills --agents            generate + install the God subagents",
    "  npx god-skills --hooks             install the hook gates (global only)",
    "",
    paint("Options", "bold"),
    "  -g, --global    install to ~/.claude (all projects)",
    "  -p, --project   install to ./.claude (this repo)",
    "  -a, --all       install every skill",
    "  -f, --force     overwrite files that already exist",
    "  -y, --yes       skip prompts, default to global",
    "      --agents    install subagents (generated from skills + manifest) + /god command",
    "      --hooks     install hook gate scripts and merge them into settings.json",
    "      --dry-run   with --agents/--hooks: print what would be installed, write nothing",
    "  -h, --help      show this",
    "  -v, --version   print the installed version",
    "",
    paint("Restart Claude Code after installing — skills and agents load at session start.", "dim"),
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

/** Resolves the install base (.claude dir), prompting when scope was not passed. */
async function resolveBase(options) {
  if (options.scope === "global") {
    return GLOBAL_BASE;
  }
  if (options.scope === "project") {
    return PROJECT_BASE;
  }
  if (options.yes || !process.stdin.isTTY) {
    return GLOBAL_BASE;
  }

  console.log("");
  console.log(`  ${paint("1", "cyan")}  Global   ${paint(GLOBAL_BASE, "dim")}`);
  console.log(`  ${paint("2", "cyan")}  Project  ${paint(PROJECT_BASE, "dim")}`);
  console.log("");
  const answer = await ask("Install where? [1] ");
  return answer === "2" ? PROJECT_BASE : GLOBAL_BASE;
}

/** Resolves short names (dev -> god-dev) against a list, exiting on unknowns. */
function resolveNames(requested, available, kind) {
  const resolved = requested.map((name) => (available.includes(name) ? name : `god-${name}`));
  const unknown = resolved.filter((name) => !available.includes(name));
  if (unknown.length > 0) {
    console.error(paint(`Unknown ${kind}(s): ${unknown.join(", ")}`, "red"));
    process.exit(1);
  }
  return resolved;
}

/** Installs the chosen skills and prints a summary. */
async function install(options) {
  const all = availableSkills();
  if (all.length === 0) {
    console.error(paint("No skills found in this package.", "red"));
    process.exit(1);
  }

  const requested =
    !options.all && options.skills.length > 0 ? resolveNames(options.skills, all, "skill") : all;

  const target = path.join(await resolveBase(options), "skills");
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

/** Strips YAML frontmatter from a SKILL.md, returning the body only. */
function stripFrontmatter(text) {
  if (!text.startsWith("---\n")) {
    return text.trim();
  }
  const end = text.indexOf("\n---\n", 4);
  if (end === -1) {
    return text.trim();
  }
  return text.slice(end + 5).trim();
}

/**
 * Generates agent files from skills + the manifest.
 * Returns [{name, content}] for the requested agents (all manifest agents by default).
 */
function generateAgents(requestedNames) {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_FILE, "utf8"));
  const available = Object.keys(manifest);
  const names =
    requestedNames.length > 0 ? resolveNames(requestedNames, available, "agent") : available;
  const handoff = fs.readFileSync(HANDOFF_FILE, "utf8").trim();

  return names.map((name) => {
    const skillFile = path.join(SOURCE_DIR, name, "SKILL.md");
    if (!fs.existsSync(skillFile)) {
      console.error(paint(`Manifest names "${name}" but skills/${name}/SKILL.md is missing.`, "red"));
      process.exit(1);
    }
    const entry = manifest[name];
    const body = stripFrontmatter(fs.readFileSync(skillFile, "utf8"));
    // Descriptions are free text and routinely contain ": " (e.g. "Read-only: ..."),
    // which is a YAML mapping token when unquoted. JSON.stringify produces a valid
    // YAML double-quoted scalar with the escaping already correct.
    const frontmatter = [
      "---",
      `name: ${name}`,
      `description: ${JSON.stringify(entry.description)}`,
      `tools: ${entry.tools}`,
      `model: ${entry.model}`,
      "---"
    ].join("\n");
    return { name, content: `${frontmatter}\n\n${body}\n\n${handoff}\n` };
  });
}

/** Generates and installs agents plus the /god command. */
async function installAgents(options) {
  const agents = generateAgents(options.skills);

  if (options.dryRun) {
    for (const agent of agents) {
      console.log(`\n${paint(`===== agents/${agent.name}.md =====`, "bold")}`);
      console.log(agent.content);
    }
    console.log(paint(`\n${agents.length} agent(s) generated (dry run — nothing written).`, "dim"));
    return;
  }

  const base = await resolveBase(options);
  const agentsDir = path.join(base, "agents");
  const commandsDir = path.join(base, "commands");
  fs.mkdirSync(agentsDir, { recursive: true });
  fs.mkdirSync(commandsDir, { recursive: true });

  const installed = [];
  const skipped = [];

  for (const agent of agents) {
    const dest = path.join(agentsDir, `${agent.name}.md`);
    if (fs.existsSync(dest) && !options.force) {
      skipped.push(agent.name);
      continue;
    }
    fs.writeFileSync(dest, agent.content);
    installed.push(agent.name);
  }

  const commandDest = path.join(commandsDir, "god.md");
  if (!fs.existsSync(commandDest) || options.force) {
    fs.copyFileSync(path.join(COMMANDS_DIR, "god.md"), commandDest);
    installed.push("/god command");
  } else {
    skipped.push("/god command");
  }

  console.log("");
  console.log(
    `${paint("✓", "green")} ${installed.length} installed to ${paint(base, "cyan")}: ${installed.join(", ")}`
  );
  if (skipped.length > 0) {
    console.log(`${paint("•", "yellow")} already present, left alone: ${skipped.join(", ")}`);
    console.log(paint("  Re-run with --force to overwrite.", "dim"));
  }
  console.log("");
  console.log(paint("Restart Claude Code to load them.", "dim"));
  console.log("");
}

/**
 * Merges the hook snippet into a settings object.
 * A snippet group is skipped when any existing hook in the same event already
 * uses the same command path. Returns the number of groups added.
 */
function mergeHookSettings(settings, snippet) {
  if (!settings.hooks) {
    settings.hooks = {};
  }
  let added = 0;
  for (const [event, groups] of Object.entries(snippet.hooks)) {
    if (!Array.isArray(settings.hooks[event])) {
      settings.hooks[event] = [];
    }
    const existingCommands = new Set(
      settings.hooks[event].flatMap((group) =>
        (group.hooks || []).map((hook) => hook.command).filter(Boolean)
      )
    );
    for (const group of groups) {
      const commands = (group.hooks || []).map((hook) => hook.command);
      if (commands.some((command) => existingCommands.has(command))) {
        continue;
      }
      settings.hooks[event].push(group);
      added += 1;
    }
  }
  return added;
}

/** Installs hook gate scripts to ~/.claude/hooks/god and merges settings.json. */
function installHooks(options) {
  if (options.scope === "project") {
    console.log(
      paint("Hooks install globally (the snippet references $HOME); ignoring --project.", "yellow")
    );
  }

  const snippet = JSON.parse(fs.readFileSync(SNIPPET_FILE, "utf8"));
  const hooksDest = path.join(GLOBAL_BASE, "hooks", "god");
  const settingsPath = path.join(GLOBAL_BASE, "settings.json");

  if (options.dryRun) {
    console.log(`Would copy hook scripts to ${hooksDest} and merge into ${settingsPath}:`);
    console.log(JSON.stringify(snippet, null, 2));
    return;
  }

  fs.mkdirSync(hooksDest, { recursive: true });
  for (const entry of fs.readdirSync(HOOKS_SOURCE_DIR)) {
    const dest = path.join(hooksDest, entry);
    fs.copyFileSync(path.join(HOOKS_SOURCE_DIR, entry), dest);
    fs.chmodSync(dest, 0o755);
  }
  console.log(`${paint("✓", "green")} hook scripts installed to ${paint(hooksDest, "cyan")}`);

  let settings = {};
  if (fs.existsSync(settingsPath)) {
    const raw = fs.readFileSync(settingsPath, "utf8");
    try {
      settings = JSON.parse(raw);
    } catch (error) {
      console.error(paint(`${settingsPath} is not valid JSON — not touching it.`, "red"));
      console.error(paint('Merge this into its "hooks" section by hand:', "yellow"));
      console.error(JSON.stringify(snippet, null, 2));
      process.exitCode = 1;
      return;
    }
    fs.copyFileSync(settingsPath, `${settingsPath}.bak`);
    console.log(paint(`  backed up settings to ${settingsPath}.bak`, "dim"));
  }

  const added = mergeHookSettings(settings, snippet);
  fs.writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`);
  if (added > 0) {
    console.log(
      `${paint("✓", "green")} ${added} hook entr${added === 1 ? "y" : "ies"} merged into ${paint(settingsPath, "cyan")}`
    );
  } else {
    console.log(paint("All hook entries were already present; settings unchanged.", "dim"));
  }
  console.log("");
  console.log(paint("Restart Claude Code to activate the gates.", "dim"));
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
  console.log(paint("Agents:  npx god-skills --agents      Hooks: npx god-skills --hooks", "dim"));
  console.log("");
}

/** Entry point. */
async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.version) {
    console.log(version);
    return;
  }

  if (options.help) {
    printHelp();
    return;
  }

  if (options.command === "list") {
    list();
    return;
  }

  if (options.agents || options.hooks) {
    if (options.agents) {
      await installAgents(options);
    }
    if (options.hooks) {
      installHooks(options);
    }
    return;
  }

  await install(options);
}

main().catch((error) => {
  console.error(paint(`Failed: ${error.message}`, "red"));
  process.exit(1);
});
