#!/bin/bash

VERSION="v2.7.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

show_help() {
    cat <<EOF
Usage: cloudgate <command> [options]

Commands:
  saml          Login to AWS via SAML (saml2aws)
  eks-allowip   Whitelist your current IP on EKS cluster publicAccessCidrs
  status        Show session status for all configured profiles

Options:
  --help             Display this help message
  --version          Display version information
  --show-commands    Show available commands

Run 'cloudgate <command> --help' for command-specific help.
EOF
}

show_commands() {
    cat <<EOF
cloudgate available commands:

  cloudgate saml                      AWS SAML login (saml2aws)
  cloudgate saml config               Configure AWS profiles
  cloudgate saml config --list        List configured profiles
  cloudgate saml --forget-password    Remove saved password from keychain
  cloudgate saml --help               Show saml help

  cloudgate eks-allowip               Whitelist your IP on EKS clusters
  cloudgate eks-allowip --help        Show eks-allowip help

  cloudgate status                    Show session status for all profiles

  cloudgate --help                    Display this help message
  cloudgate --version                 Display version information
  cloudgate --show-commands           Show this command list

EOF
}

check_dep() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo -e "${RED}Error: '$cmd' is not installed or not in PATH.${RESET}"
        echo -e "  $hint"
        exit 1
    fi
}

cmd_status() {
    local CONFIG_FILE="$HOME/.cloudgate/profiles.config"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}No profiles configured. Run 'cloudgate saml config' first.${RESET}"
        exit 0
    fi

    local profiles=()
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    if [ ${#profiles[@]} -eq 0 ]; then
        echo -e "${YELLOW}No profiles configured. Run 'cloudgate saml config' first.${RESET}"
        exit 0
    fi

    echo ""
    echo -e "${BOLD}Session status:${RESET}"
    echo ""
    for profile in "${profiles[@]}"; do
        if aws sts get-caller-identity --profile "$profile" > /dev/null 2>&1; then
            expiry=$(aws configure get aws_credential_expiration --profile "$profile" 2>/dev/null)
            if [ -n "$expiry" ]; then
                echo -e "  ${GREEN}✓${RESET} ${BOLD}$profile${RESET} ${DIM}(expires: $expiry)${RESET}"
            else
                echo -e "  ${GREEN}✓${RESET} ${BOLD}$profile${RESET} ${DIM}(valid)${RESET}"
            fi
        else
            echo -e "  ${RED}✗${RESET} ${BOLD}$profile${RESET} ${DIM}(expired — run 'cloudgate saml' to re-authenticate)${RESET}"
        fi
    done
    echo ""
}

case "$1" in
    saml)
        check_dep aws      "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        check_dep saml2aws "Install saml2aws: https://github.com/Versent/saml2aws#installation"
        shift
        cloudgate-saml "$@"
        ;;
    eks-allowip)
        check_dep aws  "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        check_dep jq   "Install jq: https://stedolan.github.io/jq/download/"
        check_dep dig  "Install bind-tools (Linux) or use macOS which includes dig by default."
        shift
        eks-allowip "$@"
        ;;
    status)
        check_dep aws "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        cmd_status
        ;;
    --version)
        echo "cloudgate $VERSION"
        ;;
    --help)
        show_help
        ;;
    --show-commands)
        show_commands
        ;;
    "")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${RESET}"
        echo ""
        show_help
        exit 1
        ;;
esac
