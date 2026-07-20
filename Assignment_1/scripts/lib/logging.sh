#!/usr/bin/env bash

COLOR_RESET='\033[0m'
COLOR_INFO='\033[0;36m'
COLOR_WARN='\033[0;33m'
COLOR_ERROR='\033[0;31m'
COLOR_SUCCESS='\033[0;32m'

# logging helpers with escape sequence for pretty printing

log_info()    { echo -e "${COLOR_INFO}[INFO]${COLOR_RESET}  $(date -Iseconds) $*"; }
log_warn()    { echo -e "${COLOR_WARN}[WARN]${COLOR_RESET}  $(date -Iseconds) $*"; }
log_error()   { echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $(date -Iseconds) $*" >&2; }
log_success() { echo -e "${COLOR_SUCCESS}[OK]${COLOR_RESET}    $(date -Iseconds) $*"; }
