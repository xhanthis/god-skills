#!/usr/bin/env node
/**
 * God Agents installer.
 *
 * Generates Claude Code subagents from `agents/manifest.json` glued to the
 * matching `god-skills` SKILL.md bodies, installs the /god router command,
 * installs the hook gates, and scaffolds the headless runner. Zero runtime
 * dependencies beyond `god-skills`, which supplies the skill bodies so an
 * agent can never drift from the skill it is generated from.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");

const { version } = require("../package.json");

const PACKAGE_ROOT = path.join(__dirname, "..");
const MANIFEST_FILE = path.join(PACKAGE_ROOT, "agents", "manifest.json");
const HANDOFF_FILE = path.join(PACKAGE_ROOT, "agents", "handoff.md");
const COMMANDS_DIR = path.join(PACKAGE_ROOT, "commands");
const HOOKS_SOURCE_DIR = path.join(PACKAGE_ROOT, "hooks", "god");
const SNIPPET_FILE = path.join(PACKAGE_ROOT, "hooks", "settings-snippet.json");
const RUNTIME_TEMPLATE_DIR = path.join(PACKAGE_ROOT, "runtime-template");

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

/**
 * Locates the skills tree that supplies agent bodies.
 * Prefers a sibling `skills/` (this repo, so tests and local edits win) and
 * falls back to the installed `god-skills` package. Exits with a fix hint when
 * neither is present, because generation cannot proceed without it.
 */
function resolveSkillsDir() {
  const sibling = path.join(PACKAGE_ROOT, "..", "skills");
  if (fs.existsSync(sibling)) {
    return sibling;
  }
  try {
    return path.join(path.dirname(require.resolve("god-skills/package.json")), "skills");
  } catch (error) {
    console.error(paint("Cannot find the god-skills package that supplies agent bodies.", "red"));
    console.error(paint("Install it alongside this one: npm i god-skills", "yellow"));
    process.exit(1);
  }
}

const SKILLS_DIR = resolveSkillsDir();

/** Parses argv into a normalised options object. */
function parseArgs(argv) {
  const options = {
    command: "install",
    agents: [],
    runtimeTarget: null,
    scope: null,
    force: false,
    yes: false,
    help: false,
    version: false,
    hooks: false,
    hooksOnly: false,
    dryRun: false
  };

  let expectRuntimeTarget = false;

  for (const arg of argv) {
    if (expectRuntimeTarget) {
      options.runtimeTarget = arg;
      expectRuntimeTarget = false;
    } else if (arg === "list" || arg === "install" || arg === "doctor") {
      options.command = arg;
    } else if (arg === "runtime") {
      options.command = "runtime";
      expectRuntimeTarget = true;
    } else if (arg === "--global" || arg === "-g") {
      options.scope = "global";
    } else if (arg === "--project" || arg === "-p") {
      options.scope = "project";
    } else if (arg === "--force" || arg === "-f") {
      options.force = true;
    } else if (arg === "--yes" || arg === "-y") {
      options.yes = true;
    } else if (arg === "--hooks") {
      options.hooks = true;
      options.hooksOnly = true;
    } else if (arg === "--all" || arg === "-a") {
      options.hooks = true;
    } else if (arg === "--dry-run") {
      options.dryRun = true;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--version" || arg === "-v") {
      options.version = true;
    } else if (!arg.startsWith("-")) {
      options.agents.push(arg);
    }
  }

  return options;
}

/** Prints usage. */
function printHelp() {
  const lines = [
    "",
    paint("God Agents", "bold") + " — Claude Code subagents, hook gates and runner",
    "",
    paint("Usage", "bold"),
    "  npx god-agents                     generate + install every agent and /god",
    "  npx god-agents god-dev god-tester  install only these agents",
    "  npx god-agents --all               agents, /god and the hook gates",
    "  npx god-agents --hooks             only the hook gates (global)",
    "  npx god-agents list                show every available agent",
    "  npx god-agents doctor              verify an existing install",
    "  npx god-agents runtime <dir>       scaffold the headless runner into <dir>",
    "",
    paint("Options", "bold"),
    "  -g, --global    install to ~/.claude (all projects)",
    "  -p, --project   install to ./.claude (this repo)",
    "  -a, --all       agents plus the hook gates",
    "  -f, --force     overwrite files that already exist",
    "  -y, --yes       skip prompts, default to global",
    "      --dry-run   print what would be installed, write nothing",
    "  -h, --help      show this",
    "  -v, --version   print the installed version",
    "",
    paint("Agent bodies come from the god-skills package — skills stay the source of truth.", "dim"),
    paint("Restart Claude Code after installing — agents load at session start.", "dim"),
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

/** Copies a directory tree recursively, preserving the executable bit. */
function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const src = path.join(from, entry.name);
    const dest = path.join(to, entry.name);
    if (entry.isDirectory()) {
      copyDir(src, dest);
    } else {
      fs.copyFileSync(src, dest);
      fs.chmodSync(dest, fs.statSync(src).mode & 0o777);
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
 * Generates agent files from the manifest plus the matching skill bodies.
 * Returns [{name, content}] for the requested agents (all manifest agents by
 * default). Exits when the manifest names a skill this install cannot supply.
 */
function generateAgents(requestedNames) {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_FILE, "utf8"));
  const available = Object.keys(manifest);
  const names =
    requestedNames.length > 0 ? resolveNames(requestedNames, available, "agent") : available;
  const handoff = fs.readFileSync(HANDOFF_FILE, "utf8").trim();

  return names.map((name) => {
    const skillFile = path.join(SKILLS_DIR, name, "SKILL.md");
    if (!fs.existsSync(skillFile)) {
      console.error(paint(`Manifest names "${name}" but ${skillFile} is missing.`, "red"));
      console.error(paint("Update god-skills: npm i god-skills@latest", "yellow"));
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
  const agents = generateAgents(options.agents);

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

/**
 * Copies runtime-template into a target directory so the unattended runner can
 * be configured in a private repo. Refuses a non-empty target without --force,
 * because the target holds the operator's own config.sh and logs.
 */
function scaffoldRuntime(options) {
  if (!options.runtimeTarget) {
    console.error(paint("Usage: npx god-agents runtime <dir>", "red"));
    process.exit(1);
  }
  const target = path.resolve(options.runtimeTarget);

  if (options.dryRun) {
    console.log(`Would copy ${RUNTIME_TEMPLATE_DIR} to ${target}`);
    return;
  }

  if (fs.existsSync(target) && fs.readdirSync(target).length > 0 && !options.force) {
    console.error(paint(`${target} is not empty — refusing to overwrite.`, "red"));
    console.error(paint("Re-run with --force if that is what you want.", "yellow"));
    process.exit(1);
  }

  copyDir(RUNTIME_TEMPLATE_DIR, target);
  console.log("");
  console.log(`${paint("✓", "green")} runner scaffolded into ${paint(target, "cyan")}`);
  console.log(paint("Next: cp config.example.sh config.sh, then read README.md.", "dim"));
  console.log("");
}

/**
 * Verifies an existing install: agents present and current, hooks wired,
 * scripts executable. Prints one line per check and exits non-zero on failure.
 */
function doctor() {
  const base = fs.existsSync(path.join(PROJECT_BASE, "agents")) ? PROJECT_BASE : GLOBAL_BASE;
  const results = [];
  const check = (ok, label, hint) => results.push({ ok, label, hint });

  const manifest = JSON.parse(fs.readFileSync(MANIFEST_FILE, "utf8"));
  const agentsDir = path.join(base, "agents");

  for (const name of Object.keys(manifest)) {
    const file = path.join(agentsDir, `${name}.md`);
    if (!fs.existsSync(file)) {
      check(false, `agent ${name}`, "run: npx god-agents");
      continue;
    }
    // Regenerating and comparing is how drift between a skill and its installed
    // agent gets caught — the whole point of generating rather than copying.
    const current = generateAgents([name])[0].content;
    const onDisk = fs.readFileSync(file, "utf8");
    check(onDisk === current, `agent ${name}`, "stale — run: npx god-agents --force");
  }

  check(
    fs.existsSync(path.join(base, "commands", "god.md")),
    "/god command",
    "run: npx god-agents"
  );

  const hooksDir = path.join(GLOBAL_BASE, "hooks", "god");
  const expectedHooks = fs.readdirSync(HOOKS_SOURCE_DIR);
  for (const script of expectedHooks) {
    const installed = path.join(hooksDir, script);
    if (!fs.existsSync(installed)) {
      check(false, `hook ${script}`, "run: npx god-agents --hooks");
      continue;
    }
    const mode = fs.statSync(installed).mode & 0o111;
    check(mode !== 0, `hook ${script}`, "not executable — run: npx god-agents --hooks");
  }

  const settingsPath = path.join(GLOBAL_BASE, "settings.json");
  if (!fs.existsSync(settingsPath)) {
    check(false, "hooks registered in settings.json", "run: npx god-agents --hooks");
  } else {
    let settings = null;
    try {
      settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
    } catch (error) {
      check(false, "settings.json parses", "fix the JSON by hand");
    }
    if (settings) {
      const snippet = JSON.parse(fs.readFileSync(SNIPPET_FILE, "utf8"));
      for (const event of Object.keys(snippet.hooks)) {
        const groups = (settings.hooks || {})[event] || [];
        const wanted = snippet.hooks[event][0].hooks[0].command;
        const present = groups.some((group) =>
          (group.hooks || []).some((hook) => hook.command === wanted)
        );
        check(present, `hook event ${event}`, "run: npx god-agents --hooks");
      }
    }
  }

  console.log("");
  console.log(paint(`Checking ${base}`, "bold"));
  console.log("");
  for (const result of results) {
    const mark = result.ok ? paint("✓", "green") : paint("✗", "red");
    const hint = result.ok ? "" : paint(`  → ${result.hint}`, "dim");
    console.log(`  ${mark} ${result.label}${hint}`);
  }
  const failed = results.filter((result) => !result.ok).length;
  console.log("");
  if (failed === 0) {
    console.log(`${paint("✓", "green")} ${results.length} checks passed.`);
  } else {
    console.log(paint(`${failed} of ${results.length} checks failed.`, "red"));
    process.exitCode = 1;
  }
  console.log("");
}

/** Prints every available agent with its tools and model. */
function list() {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_FILE, "utf8"));
  const names = Object.keys(manifest);
  console.log("");
  console.log(paint(`${names.length} agents available`, "bold"));
  console.log("");
  for (const name of names) {
    const entry = manifest[name];
    console.log(
      `  ${paint(name.padEnd(16), "cyan")} ${paint(entry.model.padEnd(7), "yellow")} ${paint(entry.tools, "dim")}`
    );
  }
  console.log("");
  console.log(paint("Install: npx god-agents <name> [...]  or  npx god-agents --all", "dim"));
  console.log(paint("Skills:  npx god-skills", "dim"));
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

  if (options.command === "doctor") {
    doctor();
    return;
  }

  if (options.command === "runtime") {
    scaffoldRuntime(options);
    return;
  }

  if (!options.hooksOnly) {
    await installAgents(options);
  }
  if (options.hooks) {
    installHooks(options);
  }
}

main().catch((error) => {
  console.error(paint(`Failed: ${error.message}`, "red"));
  process.exit(1);
});
