#!/usr/bin/env bash
# Terminal colors and formatting for demo output

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

banner() {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

section() {
    echo ""
    echo -e "${BOLD}${BLUE}--- $* ---${NC}"
    echo ""
}

pass()    { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail()    { echo -e "  ${RED}[FAIL]${NC} $*"; }
info()    { echo -e "  ${DIM}[INFO]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
result()  { echo -e "  ${BOLD}$*${NC}"; }

leaked()    { echo -e "  ${RED}${BOLD}[DATA LEAKED]${NC} $*"; }
blocked()   { echo -e "  ${GREEN}${BOLD}[BLOCKED]${NC} $*"; }
contained() { echo -e "  ${GREEN}${BOLD}[CONTAINED]${NC} $*"; }
compromised() { echo -e "  ${RED}${BOLD}[HOST COMPROMISED]${NC} $*"; }
