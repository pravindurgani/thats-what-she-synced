#!/usr/bin/env bash
#
# bench-notch.sh — what does the notch island cost this Mac, per state, with the
# Office edition on and off?
#
# Measures the running app (and WindowServer, where Core Animation renders) in:
#   rest    closed island at rest: no agent strip, no music activity
#   agents  the agents strip (needs a Claude/Codex session working meanwhile;
#           an agent running this script counts, since it is busy waiting on it)
#   music   the closed music strip (only if Music or Spotify is already playing;
#           the script never starts, stops or changes playback)
# each with notchOfficeEditionEnabled on and off, so OFF is the upstream baseline.
#
# Per run: CPU % from ps CPU-time deltas, top's %CPU, idle wakeups per second,
# top's energy-impact POWER, memory, and WindowServer's CPU over the same window.
#
# No sudo. It quits and relaunches only the app under test, backs up the whole
# defaults domain first and restores it exactly at the end (also on Ctrl-C):
# import the backup, delete any key the backup did not have, then compare.
#
# Usage:
#   Tools/bench-notch.sh                         # all states, on and off, 60 s each
#   Tools/bench-notch.sh --duration 90 --states rest,music --rounds 2
#   Tools/bench-notch.sh --out bench/after --compare bench/before/results.csv
#   Tools/bench-notch.sh --sample                # also save a 10 s `sample` per run
#
# WindowServer also draws every other app, so its CPU moves with whatever else
# is on screen: compare runs taken minutes apart on a quiet desktop, prefer
# --rounds 2 or more (the on/off order alternates each round), and read a
# difference under about a point of app CPU as noise unless it repeats. Each
# run's notes column says when the screen was locked (the lock screen's island
# was measured), the song stopped, or someone used the Mac meanwhile.
#
# Options:
#   --duration S    measured seconds per run (default 60)
#   --settle S      seconds after launch before measuring (default 20); then it
#                   waits for the app to go quiet (two 5 s windows under
#                   --quiet-cpu percent, default 5), up to --max-settle S (150)
#   --rounds N      repeat every state and mode N times; the summary is the mean
#   --states LIST   comma list of rest,agents,music (default all three)
#   --modes LIST    comma list of on,off (default on,off)
#   --out DIR       where results.csv, raw top logs and samples go
#   --compare CSV   a previous results.csv; prints before -> after per state
#   --sample        save a 10 s `sample` of the app per run (adds 10 s each)
#   --fake-agent    show the agents strip without a real agent: the app's Claude
#                   profile setting points at a folder under --out holding a
#                   session whose turn stays open while the agents runs last
#                   (and, for every run, in place of ~/.claude, which is never
#                   read or written); restored with the rest of the domain
#   --set K=T:V     also `defaults write DOMAIN K -T V` for every run, e.g.
#                   --set notchMascotStyle=string:scarn pins the companion,
#                   which Shuffle otherwise deals again with each new song
#   --app NAME / --app-path PATH / --process NAME / --domain ID
#                   the app under test (default: Vorssaint (Developer))
#
set -euo pipefail

APP_NAME="Vorssaint (Developer)"
APP_PATH="/Applications/Vorssaint (Developer).app"
PROC="VorssaintDeveloper"
DOMAIN="com.vorssaint.utils.dev"
DURATION=60
SETTLE=20
MAX_SETTLE=150
QUIET_CPU=5
ROUNDS=1
INTERVAL=2
STATES="rest,agents,music"
MODES="on,off"
OUT=""
COMPARE=""
SAMPLE=0
FAKE_AGENT=0
EXTRA_SETS=()

usage() { sed -n '2,/^set -euo/p' "$0" | sed -e '/^set -euo/d' -e 's/^# \{0,1\}//'; }

while (($#)); do
    case "$1" in
        --duration) DURATION="$2"; shift ;;
        --settle) SETTLE="$2"; shift ;;
        --max-settle) MAX_SETTLE="$2"; shift ;;
        --quiet-cpu) QUIET_CPU="$2"; shift ;;
        --rounds) ROUNDS="$2"; shift ;;
        --states) STATES="$2"; shift ;;
        --modes) MODES="$2"; shift ;;
        --out) OUT="$2"; shift ;;
        --compare) COMPARE="$2"; shift ;;
        --sample) SAMPLE=1 ;;
        --fake-agent) FAKE_AGENT=1 ;;
        --set) EXTRA_SETS+=("$2"); shift ;;
        --app) APP_NAME="$2"; shift ;;
        --app-path) APP_PATH="$2"; shift ;;
        --process) PROC="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

[[ -d "$APP_PATH" ]] || { echo "no app at $APP_PATH" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="${TMPDIR:-/tmp}/bench-notch-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
RESULTS="$OUT/results.csv"
BACKUP="$OUT/defaults-backup.plist"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

# A locked screen shows the lock screen's island, not the state asked for.
screen_locked() {
    local session
    session="$(ioreg -a -l -d 1 -k IOConsoleUsers 2>/dev/null | plutil -p - 2>/dev/null || true)"
    [[ "$session" == *'"CGSSessionScreenIsLocked" => true'* ]]
}

# Seconds since the last keyboard, pointer or trackpad input.
user_idle() {
    local idle
    idle="$(ioreg -c IOHIDSystem -d 4 2>/dev/null | awk '/HIDIdleTime/ { idle = int($NF / 1000000000) } END { print idle + 0 }')"
    echo "${idle:-0}"
}

# ps prints CPU time as [[d-]h:]mm:ss.ss; macOS usually as mmm:ss.ss.
cpu_seconds() {
    ps -o time= -p "$1" 2>/dev/null | awk '{
        t = $1; d = 0
        if (index(t, "-")) { split(t, dd, "-"); d = dd[1]; t = dd[2] }
        n = split(t, p, ":"); s = 0
        for (i = 1; i <= n; i++) s = s * 60 + p[i]
        printf "%.3f\n", s + d * 86400
    }'
}

app_pid() { pgrep -x "$PROC" | head -1; }

app_was_running=0
[[ -n "$(app_pid)" ]] && app_was_running=1

quit_app() {
    local pid; pid="$(app_pid)"
    [[ -z "$pid" ]] && return 0
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.5
    done
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.5
    done
    echo "warning: $PROC ($pid) did not quit" >&2
}

launch_app() {
    open "$APP_PATH"
    for _ in $(seq 1 60); do
        [[ -n "$(app_pid)" ]] && return 0
        sleep 0.5
    done
    echo "error: $PROC did not start" >&2
    return 1
}

# Top-level keys of a plist, one per line.
plist_keys() { plutil -p "$1" | sed -n 's/^  "\(.*\)" => .*/\1/p' | sort; }

defaults export "$DOMAIN" "$BACKUP"
echo "defaults backup: $BACKUP"

# --fake-agent: a working Claude session of the script's own. The app's
# Claude profile setting is pointed at a folder under OUT holding a session
# log whose turn is open (a prompt, then a line every few seconds), so the
# agents strip shows without a real agent at work; the setting goes back
# with the rest of the domain. Nothing under ~/.claude is read or written.
FAKE_HOME="$OUT/fake-claude"
keepalive_pid=""
fake_session_begin() {
    local log="$FAKE_HOME/projects/bench/bench-notch.jsonl" stamp
    stamp="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    printf '{"type":"user","timestamp":"%s","sessionId":"bench-notch","cwd":"%s","message":{"role":"user","content":"bench-notch"}}\n' \
        "$stamp" "$FAKE_HOME" > "$log"
    ( while :; do sleep 5; echo '{"type":"progress"}' >> "$log"; done ) &
    keepalive_pid=$!
}
fake_session_end() {
    [[ -n "$keepalive_pid" ]] && kill "$keepalive_pid" 2>/dev/null || true
    keepalive_pid=""
    rm -f "$FAKE_HOME/projects/bench/bench-notch.jsonl"
}
if ((FAKE_AGENT)); then
    mkdir -p "$FAKE_HOME/projects/bench"
    chmod 755 "$FAKE_HOME" "$FAKE_HOME/projects" "$FAKE_HOME/projects/bench"
    echo '{}' > "$FAKE_HOME/.claude.json"
    chmod 644 "$FAKE_HOME/.claude.json"
    EXTRA_SETS+=("notchAgentsClaudeProfile=string:$FAKE_HOME")
fi

restored=0
restore() {
    ((restored)) && return 0
    restored=1
    fake_session_end
    echo
    echo "▸ restoring $DOMAIN"
    quit_app
    defaults import "$DOMAIN" "$BACKUP"
    # `defaults import` merges: delete what the backup did not have.
    local now_plist="$OUT/defaults-after.plist"
    defaults export "$DOMAIN" "$now_plist"
    comm -13 <(plist_keys "$BACKUP") <(plist_keys "$now_plist") | while IFS= read -r key; do
        [[ -n "$key" ]] && defaults delete "$DOMAIN" "$key"
    done
    defaults export "$DOMAIN" "$now_plist"
    plutil -convert xml1 -o "$OUT/.before.xml" "$BACKUP"
    plutil -convert xml1 -o "$OUT/.after.xml" "$now_plist"
    if cmp -s "$OUT/.before.xml" "$OUT/.after.xml"; then
        echo "  defaults restored exactly (byte-identical export)"
    else
        echo "  WARNING: defaults differ from the backup:" >&2
        diff "$OUT/.before.xml" "$OUT/.after.xml" >&2 || true
    fi
    rm -f "$OUT/.before.xml" "$OUT/.after.xml"
    if ((app_was_running)); then
        launch_app && echo "  relaunched $APP_NAME"
    fi
}
trap restore EXIT
trap 'exit 130' INT TERM

player_playing() {
    local st=""
    if pgrep -x Music >/dev/null; then
        st="$(osascript -e 'if application "Music" is running then tell application "Music" to player state as string' 2>/dev/null || true)"
        [[ "$st" == playing ]] && { echo Music; return 0; }
    fi
    if pgrep -x Spotify >/dev/null; then
        st="$(osascript -e 'if application "Spotify" is running then tell application "Spotify" to player state as string' 2>/dev/null || true)"
        [[ "$st" == playing ]] && { echo Spotify; return 0; }
    fi
    return 1
}

set_state() { # state mode
    local office=true agents=false music=false
    [[ "$2" == off ]] && office=false
    case "$1" in
        rest) ;;
        agents) agents=true ;;
        music) music=true ;;
    esac
    defaults write "$DOMAIN" notchOfficeEditionEnabled -bool "$office"
    defaults write "$DOMAIN" notchAgentsLiveActivity -bool "$agents"
    defaults write "$DOMAIN" notchShowPlayingMusic -bool "$music"
    # --set KEY=TYPE:VALUE, as `defaults write DOMAIN KEY -TYPE VALUE`.
    local set key type
    for set in ${EXTRA_SETS[@]+"${EXTRA_SETS[@]}"}; do
        key="${set%%=*}"; type="${set#*=}"; type="${type%%:*}"
        defaults write "$DOMAIN" "$key" "-$type" "${set#*:}"
    done
}


# Summarise one top log for one pid: mean %CPU and POWER over the samples after
# the first (top's first sample has no interval), idle wakeups per second from
# the cumulative IDLEW counter, the last MEM in MB, and the median %CPU, the
# "steady" figure: a burst of log reading in the window moves the mean, not
# the median. top sometimes stops updating IDLEW for a run; a counter that
# never moves is reported as NA.
summarise_top() { # file pid seconds
    awk -v pid="$2" -v seconds="$3" '
        function mb(v) {
            if (v ~ /G$/) return v * 1024
            if (v ~ /K$/) return v / 1024
            if (v ~ /B$/ && v !~ /[KMG]B$/) return v / 1048576
            return v + 0
        }
        $1 == pid {
            n++
            gsub(/[+-]$/, "", $3); gsub(/[+-]$/, "", $5)
            if (n == 1) { w0 = $3; next }
            cpu += $2; pw += $4; w1 = $3; mem = mb($5); m++
            v[m] = $2 + 0
            for (i = m; i > 1 && v[i - 1] > v[i]; i--) { t = v[i]; v[i] = v[i - 1]; v[i - 1] = t }
        }
        END {
            if (m == 0) { print "NA,NA,NA,NA,NA"; exit }
            wake = (w1 == w0) ? "NA" : sprintf("%.1f", (w1 - w0) / seconds)
            median = (m % 2) ? v[(m + 1) / 2] : (v[m / 2] + v[m / 2 + 1]) / 2
            printf "%.2f,%s,%.2f,%.0f,%.2f\n", cpu / m, wake, pw / m, mem, median
        }' "$1"
}

# A fresh launch reads every agent log and the music state before it rests,
# which can outlast a fixed wait. After SETTLE, wait (up to MAX_SETTLE) for two
# quiet 5 s windows in a row, under QUIET_CPU percent of a core.
wait_quiet() { # pid
    local waited=0 calm=0 c0 c1
    while ((waited < MAX_SETTLE - SETTLE)); do
        c0="$(cpu_seconds "$1")"; sleep 5; c1="$(cpu_seconds "$1")"
        waited=$((waited + 5))
        if awk -v a="$c0" -v b="$c1" -v q="$QUIET_CPU" 'BEGIN { exit !((b - a) / 5 * 100 < q) }'; then
            calm=$((calm + 1)); ((calm >= 2)) && return 0
        else
            calm=0
        fi
    done
    echo "  warning: still busy after ${MAX_SETTLE}s; measuring anyway" >&2
}

measure() { # state mode round
    local state="$1" mode="$2" round="$3" pid ws a0 a1 w0 w1 t0 t1 elapsed samples tag
    tag="$state-$mode-$round"
    echo "▸ $tag: relaunching with the Office edition $mode"
    quit_app
    set_state "$state" "$mode"
    if ((FAKE_AGENT)) && [[ "$state" == agents ]]; then fake_session_begin; fi
    launch_app
    sleep "$SETTLE"
    pid="$(app_pid)"; ws="$(pgrep -x WindowServer | head -1)"
    wait_quiet "$pid"
    samples=$((DURATION / INTERVAL + 1))
    local locked=0
    screen_locked && locked=1
    t0="$(now)"; a0="$(cpu_seconds "$pid")"; w0="$(cpu_seconds "$ws")"
    top -l "$samples" -s "$INTERVAL" -pid "$pid" -pid "$ws" \
        -stats pid,cpu,idlew,power,mem > "$OUT/top-$tag.txt" 2>&1
    t1="$(now)"; a1="$(cpu_seconds "$pid")"; w1="$(cpu_seconds "$ws")"
    elapsed="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')"
    # top's IDLEW window is (samples - 1) intervals, not the wall time.
    local topwin=$(((samples - 1) * INTERVAL))
    local app ws_sum app_ps ws_ps
    app="$(summarise_top "$OUT/top-$tag.txt" "$pid" "$topwin")"
    ws_sum="$(summarise_top "$OUT/top-$tag.txt" "$ws" "$topwin")"
    app_ps="$(awk -v a="$a0" -v b="$a1" -v e="$elapsed" 'BEGIN { printf "%.2f", (b - a) / e * 100 }')"
    ws_ps="$(awk -v a="$w0" -v b="$w1" -v e="$elapsed" 'BEGIN { printf "%.2f", (b - a) / e * 100 }')"
    if ((SAMPLE)); then
        sample "$pid" 10 -file "$OUT/sample-$tag.txt" >/dev/null 2>&1 || true
    fi
    fake_session_end
    # What may make this run unlike the state it names.
    local notes=""
    if ((locked)) || screen_locked; then
        notes+="locked "
        echo "  warning: the screen was locked; this is the lock screen's island" >&2
    fi
    if [[ "$state" == music ]] && ! player_playing >/dev/null; then
        notes+="song-stopped "
        echo "  warning: the song stopped during this run; its numbers are not the music state's" >&2
    fi
    # Someone using the Mac moves WindowServer's figure more than the island does.
    if (($(user_idle) < topwin)); then notes+="user-active "; fi
    notes="${notes% }"
    echo "$state,$mode,$app_ps,$app,$ws_ps,$ws_sum,$elapsed,$round,$notes" >> "$RESULTS"
    echo "  app CPU ${app_ps}%  WindowServer ${ws_ps}%${notes:+  ($notes)}"
}


# Mean per state and mode over the rounds, NA readings left out. Columns 3-14
# of results.csv, after the state, the mode and the number of runs.
aggregate() { # results.csv
    awk -F, 'NR > 1 {
        k = $1 "," $2
        if (!(k in runs)) order[++keys] = k
        runs[k]++
        for (i = 3; i <= 14; i++) if ($i != "NA" && $i != "") { sum[k, i] += $i; cnt[k, i]++ }
    }
    END {
        for (j = 1; j <= keys; j++) {
            k = order[j]; line = k "," runs[k]
            for (i = 3; i <= 14; i++) line = line "," (cnt[k, i] ? sprintf("%.2f", sum[k, i] / cnt[k, i]) : "NA")
            print line
        }
    }' "$1"
}

COLUMNS_CSV="state,mode,app_cpu_ps,app_cpu_top,app_idlew_s,app_power,app_mem_mb,app_cpu_median,ws_cpu_ps,ws_cpu_top,ws_idlew_s,ws_power,ws_mem_mb,ws_cpu_median,seconds,round,notes"
echo "$COLUMNS_CSV" > "$RESULTS"
echo "results: $RESULTS"
echo "machine: $(sysctl -n hw.model) · macOS $(sw_vers -productVersion) · $(pmset -g batt | sed -n "2s/.*; \([a-z ]*\);.*/\1/p")"

IFS=, read -r -a state_list <<< "$STATES"
IFS=, read -r -a mode_list <<< "$MODES"
playing=""
if [[ ",$STATES," == *,music,* ]]; then
    if player="$(player_playing)"; then
        playing="$player"; echo "▸ music: $player is playing"
    else
        echo "▸ music: skipped, nothing is playing (start a song yourself and rerun)"
    fi
fi
[[ ",$STATES," == *,agents,* ]] && echo "▸ agents: the strip shows only while an agent session is working"
for ((round = 1; round <= ROUNDS; round++)); do
    for state in "${state_list[@]}"; do
        [[ "$state" == music && -z "$playing" ]] && continue
        # Alternate the order each round, so a drift in the background
        # (another app, the battery, the temperature) does not favour one mode.
        if ((round % 2)); then order=("${mode_list[@]}"); else
            order=(); for ((i = ${#mode_list[@]} - 1; i >= 0; i--)); do order+=("${mode_list[i]}"); done
        fi
        for mode in "${order[@]}"; do
            measure "$state" "$mode" "$round"
        done
    done
done


# Aggregated columns: 1 state, 2 mode, 3 runs, 4 app CPU (ps), 5 app CPU (top
# mean), 6 wake/s, 7 power, 8 mem, 9 app steady (median), 10 WS CPU (ps),
# 11 WS top mean, 12 WS wake/s, 13 WS power, 14 WS mem, 15 WS steady.
summary="$(aggregate "$RESULTS")"
echo
echo "App = $PROC, WS = WindowServer, mean of $ROUNDS round(s). CPU% from ps CPU-time"
echo "deltas; steady = median of top's 2 s samples, which a burst does not move;"
echo "wake/s = idle wakeups per second; power = top's energy impact; mem = MB."
echo "NA: top did not report idle wakeups for that run."
printf '%-7s %-4s | %7s %7s %7s %7s %6s | %7s %7s %7s\n' state mode "CPU%" steady "wake/s" power mem "WS CPU%" steady "WS pow"
echo "$summary" | awk -F, '{
    printf "%-7s %-4s | %7.2f %7.2f %7s %7.2f %6.0f | %7.2f %7.2f %7.2f\n", $1, $2, $4, $9, $6, $7, $8, $10, $15, $13
}'

awk -F, 'NR > 1 && $17 != "" { if (!shown++) print "Runs with notes:"; printf "  %s-%s-%s: %s\n", $1, $2, $16, $17 }' "$RESULTS"

# ON minus OFF per state: the Office edition's own cost.
echo
echo "Office edition cost (on - off):"
echo "$summary" | awk -F, '
    function d(a, b) { return (a == "NA" || b == "NA") ? "    NA" : sprintf("%+6.2f", a - b) }
    { k = $1; if ($2 == "on") on[k] = $0; else off[k] = $0; if (!(k in seen)) order[++n] = k; seen[k] = 1 }
    END {
        for (j = 1; j <= n; j++) { k = order[j]; if ((k in on) && (k in off)) {
            split(on[k], a, ","); split(off[k], b, ",")
            printf "  %-7s CPU %s (steady %s) pts  wake/s %s  power %s  mem %s MB  WS %s (steady %s) pts\n", k, d(a[4], b[4]), d(a[9], b[9]), d(a[6], b[6]), d(a[7], b[7]), d(a[8], b[8]), d(a[10], b[10]), d(a[15], b[15])
        } }
    }'

if [[ -n "$COMPARE" && -f "$COMPARE" ]]; then
    echo
    echo "Against $COMPARE (before -> after):"
    { aggregate "$COMPARE" | sed 's/^/B,/'; echo "$summary" | sed 's/^/A,/'; } | awk -F, '
        $1 == "B" { prev[$2 "," $3] = $0; next }
        ($2 "," $3) in prev {
            split(prev[$2 "," $3], b, ",")
            printf "  %-7s %-4s CPU %6.2f -> %6.2f  steady %5.2f -> %5.2f  wake/s %6s -> %6s  power %6.2f -> %6.2f  WS %6.2f -> %6.2f\n", $2, $3, b[5], $5, b[10], $10, b[7], $7, b[8], $8, b[11], $11
        }'
fi
