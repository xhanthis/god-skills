#!/usr/bin/env bash
# God runtime configuration. Copy to config.sh and fill in.
# Kept separate from run.sh so template updates never clobber your settings,
# and so the runners can be tested against a scratch config.
#
#   cp config.example.sh config.sh && $EDITOR config.sh

# Repos the nightly tester works on. Needs a runnable test suite.
REPOS=({{REPO_PATHS}})                 # e.g. ("$HOME/code/backend" "$HOME/code/admin_app")

# Repos the weekly scout reads. May include repos with no test harness,
# since scout is read-only analysis.
SCOUT_REPOS=({{SCOUT_REPO_PATHS}})

# Branch the nightly runner branches from and never commits to.
DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"

# Guardrails. Enforced in shell, not in prompts: a prompt can be talked out
# of a limit, a script cannot.
GOD_COST_CAP="${GOD_COST_CAP:-10}"           # USD per nightly run, all repos
GOD_SCOUT_COST_CAP="${GOD_SCOUT_COST_CAP:-8}" # USD per weekly scout run
GOD_PR_CAP="${GOD_PR_CAP:-3}"                # PRs per repo per night

# Linear. Prefer reading the token from the Keychain over hardcoding it here.
#
# Agents write into your normal team alongside human work. What keeps their
# findings identifiable is authorship, and what keeps them out of your views is
# the label — so both matter more here than they would in a separate team.
#
# For issues to be authored by "God" rather than by you, LINEAR_API_KEY must be
# an OAuth app token authorized with actor=app. A personal key (lin_api_...)
# still works, but every issue will be authored by the key's owner.
# Run `./linear/client.sh whoami` to see which you have.
export LINEAR_API_KEY="${LINEAR_API_KEY:-$(security find-generic-password -a "$USER" -s god-linear -w 2>/dev/null)}"
export LINEAR_TEAM_ID="${LINEAR_TEAM_ID:-{{LINEAR_TEAM_ID}}}"

export GOD_ACTOR_NAME="${GOD_ACTOR_NAME:-God}"   # shown as the issue author
export GOD_ACTOR_ICON="${GOD_ACTOR_ICON:-}"      # optional avatar URL
export GOD_LABEL="${GOD_LABEL:-god}"             # created on first use if absent
