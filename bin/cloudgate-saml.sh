#!/bin/bash

CONFIG_DIR="$HOME/.cloudgate"
CONFIG_FILE="$CONFIG_DIR/profiles.config"
VERSION="v1.3.0"

load_profiles() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        profiles=()
    fi
}

save_profiles() {
    mkdir -p "$CONFIG_DIR"
    echo "profiles=(" > "$CONFIG_FILE"
    for profile in "${profiles[@]}"; do
        echo "    \"$profile\"" >> "$CONFIG_FILE"
    done
    echo ")" >> "$CONFIG_FILE"
}

config_profiles() {
    echo "Enter the AWS profiles (one per line). Enter an empty line to finish:"
    profiles=()
    while :; do
        read -r -p "Profile: " profile
        [ -z "$profile" ] && break
        profiles+=("$profile")
    done
    save_profiles
    echo "Profiles saved to $CONFIG_FILE"
}

display_help() {
    cat <<EOF
Usage: cloudgate saml [OPTION]

Options:
  config              Configure the AWS profiles for SAML authentication.
  --help              Display this help message and exit.
  --version           Display version information and exit.
  --show-commands     Show available commands and exit.

Description:
  Authenticates to multiple AWS accounts using SAML (saml2aws) and updates
  kubeconfig for all EKS clusters in eu-west-1 and eu-central-1.

  After login, optionally runs 'cloudgate eks-allowip' to whitelist your IP.

Example:
  cloudgate saml config   # first-time setup
  cloudgate saml          # authenticate and update kubeconfigs

EOF
}

display_version() {
    echo "cloudgate saml $VERSION"
}

display_commands() {
    cat <<EOF
cloudgate available commands:

  cloudgate saml                  AWS SAML login (saml2aws)
  cloudgate saml config           Configure AWS profiles
  cloudgate saml --help           Show help
  cloudgate saml --version        Show version
  cloudgate saml --show-commands  Show this command list

  cloudgate eks-allowip           Whitelist your IP on EKS clusters
  cloudgate --show-commands       Show all cloudgate commands

EOF
}

read_password() {
    prompt=$1
    password=""
    while IFS= read -r -p "$prompt" -s -n 1 char; do
        if [[ $char == $'\0' ]]; then
            break
        fi
        prompt='*'
        password+="$char"
    done
    echo
}

if [ "$1" == "--help" ]; then
    display_help
    exit 0
fi

if [ "$1" == "--version" ]; then
    display_version
    exit 0
fi

if [ "$1" == "--show-commands" ]; then
    display_commands
    exit 0
fi

if [ "$1" == "config" ]; then
    config_profiles
    exit 0
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

load_profiles

if [ ${#profiles[@]} -eq 0 ]; then
    echo -e "${RED}✗ No profiles found. Please run 'cloudgate saml config' to configure profiles.${RESET}"
    exit 1
fi

if [ -z "$SAML_EMAIL" ]; then
    read -r -p "Enter the email: " SAML_EMAIL
    export SAML_EMAIL
else
    echo -e "${DIM}Using email: $SAML_EMAIL${RESET}"
fi

read_password "Enter the password: "

echo ""
echo -e "${BOLD}Available AWS Accounts:${RESET}"
i=1
for profile in "${profiles[@]}"; do
    echo -e "  ${CYAN}$i)${RESET} ${BOLD}$profile${RESET}"
    ((i++))
done
echo ""

read -r -p "Enter the numbers of the profiles you want to use, separated by commas (e.g., 1,3,5): " selected_profiles

IFS=',' read -ra profile_indices <<< "$selected_profiles"

login_with_profile() {
    local profile=$1
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "🔐 ${BOLD}Logging in with profile: ${CYAN}$profile${RESET}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    sed -i '' '/aws_profile/d' ~/.saml2aws
    echo "aws_profile             = $profile" >> ~/.saml2aws

    saml2aws login --force --username="$SAML_EMAIL" --password="$password" --skip-prompt
}

for index in "${profile_indices[@]}"; do
    profile=${profiles[$((index-1))]}
    if [ -n "$profile" ]; then
        login_with_profile "$profile"
    else
        echo -e "${RED}✗ Invalid profile selection: $index. Skipping.${RESET}"
    fi
done

echo ""
echo -e "${GREEN}✓ Completed login for all selected profiles.${RESET}"
unset password

regions=(
    "eu-west-1"
    "eu-central-1"
)

echo ""
echo -e "${BOLD}Updating kubeconfigs...${RESET}"
for region in "${regions[@]}"; do
    for index in "${profile_indices[@]}"; do
        profile=${profiles[$((index-1))]}
        if [ -n "$profile" ]; then
            clusters=$(aws eks list-clusters --output text --profile "$profile" --region "$region" 2>/dev/null | awk '{print $2}')
            while read -r cluster; do
                [ -z "$cluster" ] && continue
                if aws eks update-kubeconfig --region "$region" --name "$cluster" --profile "$profile" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✓${RESET} ${BOLD}$cluster${RESET} ${DIM}($region ← $profile)${RESET}"
                else
                    echo -e "  ${RED}✗${RESET} Failed to update kubeconfig for ${BOLD}$cluster${RESET} ${DIM}($region ← $profile)${RESET}"
                fi
            done <<< "$clusters"
        fi
    done
done

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  💡 ${DIM}All clusters (lower and higher) are restricted to${RESET}"
echo -e "  ${DIM}Vodafone VPN. Whitelist your IP to access them.${RESET}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

read -r -p "Do you want to whitelist your IP on EKS clusters? (yes/no): " proceed

if [ "$proceed" == "yes" ]; then
    cloudgate eks-allowip
else
    echo -e "${DIM}Whitelisting skipped.${RESET}"
fi
