#!/usr/bin/env bash
set -euo pipefail

START_DIR="$(pwd)"
cd "$(dirname "$(realpath "$0")")"

DEFAULT_NAME="pdf_parser"
DEFAULT_PATH="$(pwd)/dist"
SCRIPT="main.py"
VENV_DIR="venv"
BAR_WIDTH=30
TOTAL=6
STEP=0
VERBOSE=false
LOG="$(mktemp /tmp/build_XXXXXX.log)"
BG_PID=""

# --- Colors (only if stdout is a terminal) ---
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_YELLOW=$'\033[33m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_GREEN=''; C_RED=''; C_CYAN=''; C_YELLOW=''
fi

# --- Characters (UTF-8 with ASCII fallback) ---
LOCALE_STR="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
if [[ "$(locale charmap 2>/dev/null)" == "UTF-8" \
      || "$LOCALE_STR" == *[Uu][Tt][Ff]-8* || "$LOCALE_STR" == *[Uu][Tt][Ff]8* ]]; then
    CH_FULL='█'; CH_EMPTY='░'
    SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    ICON_OK='✔'; ICON_ERR='✘'; ICON_INFO='ℹ'
else
    CH_FULL='#'; CH_EMPTY='-'
    SPINNER=('|' '/' '-' '\')
    ICON_OK='OK'; ICON_ERR='X'; ICON_INFO='i'
fi

cleanup() {
    tput cnorm 2>/dev/null || true
    rm -f "$LOG"
}
on_interrupt() {
    if [[ -n "$BG_PID" ]]; then kill "$BG_PID" 2>/dev/null || true; fi
    printf '\r\033[K\n%sInterrupted.%s\n' "$C_YELLOW" "$C_RESET"
    exit 130
}
trap cleanup EXIT
trap on_interrupt INT TERM

usage() {
    cat <<USAGE
Usage: $(basename "$0") [-v|--verbose] [-h|--help]

  -v, --verbose   Show the full output of every step
  -h, --help      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=true ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "${C_RED}${ICON_ERR} Unknown option: $1${C_RESET}" >&2; usage; exit 1 ;;
    esac
    shift
done

# --- Progress bar ---
repeat_char() {
    local n=$1 ch=$2 out='' k
    for ((k = 0; k < n; k++)); do out+="$ch"; done
    printf '%s' "$out"
}

# draw_bar <overall percent 0-100> <label> <spinner>
draw_bar() {
    local percent=$1 label=$2 spin=${3:-' '}
    local filled=$(( percent * BAR_WIDTH / 100 ))
    local empty=$(( BAR_WIDTH - filled ))

    local cols max_label
    cols=$(tput cols 2>/dev/null || echo 80)
    max_label=$(( cols - BAR_WIDTH - 12 ))
    if (( max_label < 10 )); then max_label=10; fi
    label="${label:0:max_label}"

    printf '\r\033[K%s%s%s%s%s %s%3d%%%s  %s%s%s %s' \
        "$C_GREEN" "$(repeat_char "$filled" "$CH_FULL")" \
        "$C_DIM" "$(repeat_char "$empty" "$CH_EMPTY")" "$C_RESET" \
        "$C_BOLD" "$percent" "$C_RESET" \
        "$C_CYAN" "$spin" "$C_RESET" "$label"
}

# Real PyInstaller progress: reads the log and prints "<floor> <ceiling>"
# (percent inside the build step). Milestones are checked from last to first.
build_progress() {
    if   grep -qE "Building EXE from .* completed successfully" "$LOG"; then echo "100 100"
    elif grep -q  "Appending archive"                           "$LOG"; then echo "92 100"
    elif grep -q  "Building EXE"                                "$LOG"; then echo "85 92"
    elif grep -q  "Building PKG"                                "$LOG"; then echo "75 85"
    elif grep -q  "Building PYZ"                                "$LOG"; then echo "65 75"
    elif grep -q  "Looking for dynamic libraries"               "$LOG"; then echo "55 65"
    elif grep -q  "binary vs. data reclassification"            "$LOG"; then echo "45 55"
    elif grep -q  "Processing module hooks"                     "$LOG"; then echo "25 45"
    elif grep -q  "Analyzing"                                   "$LOG"; then echo "10 25"
    else echo "3 10"
    fi
}

# run_step <label> <progress_fn or ""> <command...>
run_step() {
    local label=$1 pfn=$2; shift 2
    STEP=$((STEP + 1))

    if $VERBOSE; then
        echo
        echo "${C_BOLD}${C_CYAN}━━━ [${STEP}/${TOTAL}] ${label} ━━━${C_RESET}"
        "$@"
        echo "${C_GREEN}${ICON_OK} [${STEP}/${TOTAL}] done${C_RESET}"
        return
    fi

    # Not a terminal (pipe, IDE panel, file): one clean line per step
    if [[ ! -t 1 ]]; then
        printf '[%d/%d] %s... ' "$STEP" "$TOTAL" "$label"
        if "$@" >>"$LOG" 2>&1; then
            echo "OK"
        else
            echo "FAILED"
            tail -n 20 "$LOG" >&2
            exit 1
        fi
        return
    fi

    "$@" >>"$LOG" 2>&1 &
    BG_PID=$!

    local n=${#SPINNER[@]} i=0 cur=0 fl=0 ce=0 pct
    while kill -0 "$BG_PID" 2>/dev/null; do
        if [[ -n "$pfn" ]]; then
            if (( i % 4 == 0 )); then
                read -r fl ce <<<"$("$pfn")"
            fi
            if (( cur < fl )); then
                cur=$(( cur + (fl - cur + 2) / 3 ))        # ease up to the milestone
            elif (( cur < ce - 1 && i % 12 == 0 )); then
                cur=$(( cur + 1 ))                          # slow creep inside the stage
            fi
        fi
        pct=$(( ((STEP - 1) * 100 + cur) / TOTAL ))
        draw_bar "$pct" "$label" "${SPINNER[i % n]}"
        i=$((i + 1))
        sleep 0.08
    done

    if ! wait "$BG_PID"; then
        BG_PID=""
        printf '\r\033[K'
        echo "${C_RED}${ICON_ERR} Step failed: ${label}${C_RESET}" >&2
        echo "${C_DIM}--- last 20 log lines ---${C_RESET}" >&2
        tail -n 20 "$LOG" >&2
        echo "${C_YELLOW}Run with -v for full output.${C_RESET}" >&2
        exit 1
    fi
    BG_PID=""
    draw_bar $(( STEP * 100 / TOTAL )) "$label" "${C_GREEN}${ICON_OK}${C_RESET}"
}

# --- Inputs ---
echo "${C_BOLD}${C_CYAN}PDF Parser · build${C_RESET}"
echo

read -rp "Executable name [${DEFAULT_NAME}]: " NAME
NAME="${NAME:-$DEFAULT_NAME}"

read -rp "Output path [${DEFAULT_PATH}]: " OUT_PATH
OUT_PATH="${OUT_PATH:-$DEFAULT_PATH}"
OUT_PATH="${OUT_PATH/#\~/$HOME}"
# Relative paths count from where the command was launched
if [[ "$OUT_PATH" != /* ]]; then OUT_PATH="$START_DIR/$OUT_PATH"; fi

if [[ ! -f "$SCRIPT" ]]; then
    echo "${C_RED}${ICON_ERR} $SCRIPT not found in $(pwd)${C_RESET}" >&2
    exit 1
fi

if $VERBOSE; then
    echo "${C_CYAN}${ICON_INFO} name=$NAME  output=$OUT_PATH  script=$SCRIPT${C_RESET}"
fi

PIP_Q=(--quiet)
if $VERBOSE; then PIP_Q=(); fi

# --- Steps ---
step_venv() {
    if [[ ! -d "$VENV_DIR" ]]; then
        python3 -m venv "$VENV_DIR"
    else
        echo "venv already exists, reusing it"
    fi
}

step_pip() {
    "$VENV_DIR/bin/python" -m pip install "${PIP_Q[@]}" --upgrade pip
}

step_deps() {
    if [[ -f requirements.txt ]]; then
        "$VENV_DIR/bin/python" -m pip install "${PIP_Q[@]}" -r requirements.txt
    else
        "$VENV_DIR/bin/python" -m pip install "${PIP_Q[@]}" pypdf
    fi
}

step_pyinstaller() {
    "$VENV_DIR/bin/python" -m pip install "${PIP_Q[@]}" pyinstaller
}

step_build() {
    mkdir -p "$OUT_PATH"
    "$VENV_DIR/bin/python" -m PyInstaller --onefile --name "$NAME" \
        --distpath "$OUT_PATH" \
        --workpath build \
        --specpath build \
        --noconfirm \
        "$SCRIPT"
}

step_clean() {
    if $VERBOSE; then
        rm -rfv build
    else
        rm -rf build
    fi
    find . -name "__pycache__" -type d -not -path "./$VENV_DIR/*" -exec rm -rf {} + 2>/dev/null || true
}

echo
if ! $VERBOSE; then tput civis 2>/dev/null || true; fi

run_step "Creating virtual environment" ""             step_venv
run_step "Upgrading pip"                ""             step_pip
run_step "Installing dependencies"      ""             step_deps
run_step "Installing PyInstaller"       ""             step_pyinstaller
run_step "Building executable"          build_progress step_build
run_step "Cleaning up build files"      ""             step_clean

echo
echo
echo "${C_GREEN}${C_BOLD}${ICON_OK} Done!${C_RESET} Executable created at: ${C_BOLD}${OUT_PATH}/${NAME}${C_RESET}"