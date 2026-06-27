#!/bin/bash

CONFIG_DIR="$HOME/.cloudgate"
CONFIG_FILE="$CONFIG_DIR/profiles.config"
ROLES_FILE="$CONFIG_DIR/roles.config"
CLOUDGATE_CONFIG="$CONFIG_DIR/config"
VERSION="v2.7.0"

# Default profiles shipped with the tool — can be overridden locally
DEFAULT_PROFILES=(
    "cyberhub-aws-dev"
    "cyberhub-aws-pre-prod"
    "cyberhub-aws-prod"
    "dcaas"
    "dmmsandbox"
    "dmp-higher"
    "dotcom-lower"
    "dotcombackend"
    "ecom-lower"
    "maac"
    "maac-dev"
    "maac-mgmt"
    "maac-stage"
    "naas-higher"
    "private-vhub-dev"
    "private-vhub-prod"
    "vbesimmanager-higherenvironments"
    "vodafonebusinessesimmanager-lowerenvironment"
)

# Default account IDs and roles — role can be overridden per user with --set-role
DEFAULT_ROLES=(
    "cyberhub-aws-dev=692656050419:DevOps"
    "cyberhub-aws-pre-prod=392425245021:DevOps"
    "cyberhub-aws-prod=964759443197:DevOps"
    "dcaas=867344471150:DevOps"
    "dmmsandbox=117521914691:DevOps"
    "dmp-higher=975050100409:DevOps"
    "dotcom-lower=590183795429:DevOps"
    "dotcombackend=810248091086:DevOps"
    "ecom-lower=448618645210:DevOps"
    "maac=725756935801:DevOps"
    "maac-dev=517922549367:DevOps"
    "maac-mgmt=185664191886:DevOps"
    "maac-stage=518448139509:DevOps"
    "naas-higher=956500824817:DevOps"
    "private-vhub-dev=715519369387:DevOps"
    "private-vhub-prod=878202868047:DevOps"
    "vbesimmanager-higherenvironments=117678195562:DevOps"
    "vodafonebusinessesimmanager-lowerenvironment=523109703177:DevOps"
)

init_defaults() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "profiles=(" > "$CONFIG_FILE"
        for p in "${DEFAULT_PROFILES[@]}"; do
            echo "    \"$p\"" >> "$CONFIG_FILE"
        done
        echo ")" >> "$CONFIG_FILE"
        echo "Default profiles initialized in $CONFIG_FILE"
        echo "Run 'cloudgate saml config --set-role <profile> <role>' to customize your role."
    fi
    if [ ! -f "$ROLES_FILE" ]; then
        for entry in "${DEFAULT_ROLES[@]}"; do
            echo "$entry" >> "$ROLES_FILE"
        done
        echo "Default role mappings initialized in $ROLES_FILE"
    fi
}

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

list_profiles() {
    load_profiles
    if [ ${#profiles[@]} -eq 0 ]; then
        echo "No profiles configured. Run 'cloudgate saml config' to add profiles."
        return
    fi
    echo "Configured AWS profiles:"
    for profile in "${profiles[@]}"; do
        local arn
        arn=$(get_role_arn "$profile")
        if [ -n "$arn" ]; then
            local role_name
            role_name="${arn##*/}"
            echo "  - $profile  (role: $role_name)"
        else
            echo "  - $profile"
        fi
    done
}

get_role_arn() {
    local profile="$1"
    if [ -f "$ROLES_FILE" ]; then
        local entry account_id role_name
        entry=$(grep "^${profile}=" "$ROLES_FILE" | cut -d= -f2-)
        [ -z "$entry" ] && return
        account_id=$(echo "$entry" | cut -d: -f1)
        role_name=$(echo "$entry" | cut -d: -f2)
        role_name="${role_name:-DevOps}"
        echo "arn:aws:iam::${account_id}:role/${role_name}"
    fi
}

save_profile_role() {
    local profile="$1"
    local account_id="$2"
    local role_name="${3:-DevOps}"
    mkdir -p "$CONFIG_DIR"
    local entry="${account_id}:${role_name}"
    if grep -q "^${profile}=" "$ROLES_FILE" 2>/dev/null; then
        sed -i '' "s|^${profile}=.*|${profile}=${entry}|" "$ROLES_FILE"
    else
        echo "${profile}=${entry}" >> "$ROLES_FILE"
    fi
}

config_profiles() {
    echo "Enter the AWS profiles one by one. Enter an empty line to finish."
    echo ""
    profiles=()
    while :; do
        read -r -p "Profile name: " profile
        [ -z "$profile" ] && break
        profiles+=("$profile")
        read -r -p "AWS account ID for '$profile' (press Enter to skip): " account_id
        if [ -n "$account_id" ]; then
            read -r -p "Role name for '$profile' [DevOps]: " role_name
            role_name="${role_name:-DevOps}"
            save_profile_role "$profile" "$account_id" "$role_name"
        fi
    done
    save_profiles
    echo "Profiles saved to $CONFIG_FILE"
}

load_email() {
    [ -n "$SAML_EMAIL" ] && return
    if [ -f "$CLOUDGATE_CONFIG" ]; then
        local saml_email=""
        # shellcheck source=/dev/null
        source "$CLOUDGATE_CONFIG"
        [ -n "$saml_email" ] && SAML_EMAIL="$saml_email"
    fi
}

save_email() {
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CLOUDGATE_CONFIG" ] && grep -q '^saml_email=' "$CLOUDGATE_CONFIG"; then
        sed -i '' "s|^saml_email=.*|saml_email=\"$1\"|" "$CLOUDGATE_CONFIG"
    else
        echo "saml_email=\"$1\"" >> "$CLOUDGATE_CONFIG"
    fi
}

display_help() {
    cat <<EOF
Usage: cloudgate saml [OPTION]

Options:
  config                    Configure the AWS profiles for SAML authentication.
  config --list             List configured profiles and their roles.
  config --set-role <p> <r> Update the role for a specific profile.
  --help                    Display this help message and exit.
  --version             Display version information and exit.
  --show-commands       Show available commands and exit.
  --forget-password     Remove saved password from keychain.

Description:
  Authenticates to multiple AWS accounts using SAML (saml2aws) and updates
  kubeconfig for all EKS clusters in eu-west-1 and eu-central-1.

  Your password can be saved securely in the system keychain (macOS Keychain
  or Linux secret-tool) so you don't need to type it every time.

  After login, optionally runs 'cloudgate eks-allowip' to whitelist your IP.

Example:
  cloudgate saml config            # first-time setup
  cloudgate saml                   # authenticate and update kubeconfigs
  cloudgate saml --forget-password # clear saved password from keychain

EOF
}

display_version() {
    echo "cloudgate saml $VERSION"
}

display_commands() {
    cat <<EOF
cloudgate available commands:

  cloudgate saml                      AWS SAML login (saml2aws)
  cloudgate saml config               Configure AWS profiles
  cloudgate saml --forget-password    Remove saved password from keychain
  cloudgate saml --help               Show help
  cloudgate saml --version            Show version
  cloudgate saml --show-commands      Show this command list

  cloudgate eks-allowip           Whitelist your IP on EKS clusters
  cloudgate --show-commands       Show all cloudgate commands

EOF
}

KEYCHAIN_SERVICE="cloudgate-saml"

keychain_get() {
    if command -v security > /dev/null 2>&1; then
        security find-generic-password -a "$1" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null
    elif command -v secret-tool > /dev/null 2>&1; then
        secret-tool lookup service "$KEYCHAIN_SERVICE" account "$1" 2>/dev/null
    fi
}

keychain_set() {
    if command -v security > /dev/null 2>&1; then
        security add-generic-password -a "$1" -s "$KEYCHAIN_SERVICE" -w "$2" -U 2>/dev/null
    elif command -v secret-tool > /dev/null 2>&1; then
        printf '%s' "$2" | secret-tool store --label="cloudgate SAML password" service "$KEYCHAIN_SERVICE" account "$1" 2>/dev/null
    fi
}

keychain_delete() {
    if command -v security > /dev/null 2>&1; then
        security delete-generic-password -a "$1" -s "$KEYCHAIN_SERVICE" 2>/dev/null
    elif command -v secret-tool > /dev/null 2>&1; then
        secret-tool clear service "$KEYCHAIN_SERVICE" account "$1" 2>/dev/null
    fi
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

if [ "$1" == "--forget-password" ]; then
    if [ -z "$SAML_EMAIL" ]; then
        read -r -p "Enter the email to forget password for: " SAML_EMAIL
    fi
    keychain_delete "$SAML_EMAIL"
    echo -e "${GREEN}✓ Password removed from keychain for $SAML_EMAIL${RESET}"
    exit 0
fi

if [ "$1" == "config" ]; then
    if [ "$2" == "--list" ]; then
        list_profiles
    elif [ "$2" == "--set-role" ]; then
        if [ -z "$3" ] || [ -z "$4" ]; then
            echo "Usage: cloudgate saml config --set-role <profile> <role>"
            echo "Example: cloudgate saml config --set-role dcaas Developer"
            exit 1
        fi
        local_profile="$3"
        local_role="$4"
        if [ ! -f "$ROLES_FILE" ] || ! grep -q "^${local_profile}=" "$ROLES_FILE" 2>/dev/null; then
            echo "Profile '$local_profile' not found in $ROLES_FILE"
            echo "Run 'cloudgate saml config --list' to see configured profiles."
            exit 1
        fi
        current_entry=$(grep "^${local_profile}=" "$ROLES_FILE" | cut -d= -f2-)
        account_id=$(echo "$current_entry" | cut -d: -f1)
        sed -i '' "s|^${local_profile}=.*|${local_profile}=${account_id}:${local_role}|" "$ROLES_FILE"
        echo "Role for '$local_profile' updated to '$local_role'"
    else
        config_profiles
    fi
    exit 0
fi

# Colors — Vodafone brand palette
VF_RED='\033[38;2;230;0;0m'    # Vodafone Red #E60000
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

init_defaults

load_profiles

if [ ${#profiles[@]} -eq 0 ]; then
    echo -e "${RED}✗ No profiles found. Please run 'cloudgate saml config' to configure profiles.${RESET}"
    exit 1
fi

load_email
if [ -z "$SAML_EMAIL" ]; then
    read -r -p "Enter the email: " SAML_EMAIL
    export SAML_EMAIL
    read -r -p "Save email for next time? (yes/no): " save_em
    if [ "$save_em" == "yes" ]; then
        save_email "$SAML_EMAIL"
        echo -e "${GREEN}✓ Email saved to ~/.cloudgate/config${RESET}"
    fi
else
    echo -e "${DIM}Using email: $SAML_EMAIL${RESET}"
fi

password=$(keychain_get "$SAML_EMAIL")
if [ -n "$password" ]; then
    echo -e "${GREEN}🔑 Using saved password from keychain.${RESET} ${DIM}(run 'cloudgate saml --forget-password' to clear)${RESET}"
else
    read_password "Enter the password: "
    read -r -p "Save password to keychain for next time? (yes/no): " save_pw
    if [ "$save_pw" == "yes" ]; then
        keychain_set "$SAML_EMAIL" "$password"
        echo -e "${GREEN}✓ Password saved to keychain.${RESET}"
    fi
fi

echo ""
echo -e "${BOLD}Available AWS Accounts:${RESET}"
i=1
for profile in "${profiles[@]}"; do
    echo -e "  ${VF_RED}$i)${RESET} ${BOLD}$profile${RESET}"
    ((i++))
done
echo ""

read -r -p "Enter the numbers of the profiles you want to use, separated by commas (e.g., 1,3,5): " selected_profiles

IFS=',' read -ra profile_indices <<< "$selected_profiles"

failed_profiles=()

login_with_profile() {
    local profile=$1
    local current=$2
    local total=$3
    echo ""
    echo -e "${VF_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "🔐 ${BOLD}[${current}/${total}] Logging in with profile: ${VF_RED}$profile${RESET}"
    echo -e "${VF_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    sed -i '' '/aws_profile/d' ~/.saml2aws
    sed -i '' '/role_arn/d' ~/.saml2aws
    echo "aws_profile             = $profile" >> ~/.saml2aws

    local role_arn
    role_arn=$(get_role_arn "$profile")
    if [ -n "$role_arn" ]; then
        echo "role_arn                = $role_arn" >> ~/.saml2aws
        echo -e "  ${DIM}Using role: $role_arn${RESET}"
    fi

    local tmpfile
    tmpfile=$(mktemp)
    saml2aws login --force --username="$SAML_EMAIL" --password="$password" --skip-prompt --session-duration 43200 2>&1 | tee "$tmpfile"
    local exit_code="${PIPESTATUS[0]}"
    local saml_output
    saml_output=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ "$exit_code" -eq 0 ]; then
        echo -e "  ${GREEN}✓ Login successful for ${BOLD}$profile${RESET}"
        return 0
    else
        if echo "$saml_output" | grep -qi "MFA BeginAuth\|throttl\|too many\|spam\|AADSTS90025"; then
            echo -e "  ${RED}✗ Azure AD MFA throttled for ${BOLD}$profile${RESET}"
            echo -e "  ${DIM}  Wait a few minutes before retrying — Azure AD is blocking rapid MFA requests.${RESET}"
        elif echo "$saml_output" | grep -qi "password\|credential\|invalid\|unauthorized"; then
            echo -e "  ${RED}✗ Login failed for ${BOLD}$profile${RESET} ${DIM}(wrong password — run 'cloudgate saml --forget-password')${RESET}"
        else
            echo -e "  ${RED}✗ Login failed for ${BOLD}$profile${RESET}"
        fi
        failed_profiles+=("$profile")
        return 1
    fi
}

succeeded_indices=()
total_selected=${#profile_indices[@]}
current_num=0
for index in "${profile_indices[@]}"; do
    ((current_num++))
    profile=${profiles[$((index-1))]}
    if [ -n "$profile" ]; then
        if login_with_profile "$profile" "$current_num" "$total_selected"; then
            succeeded_indices+=("$index")
        fi
    else
        echo -e "${RED}✗ Invalid profile selection: $index. Skipping.${RESET}"
    fi
done

echo ""
if [ ${#failed_profiles[@]} -gt 0 ]; then
    echo -e "${RED}✗ Login failed for: ${failed_profiles[*]}${RESET}"
fi
if [ ${#succeeded_indices[@]} -eq 0 ]; then
    echo -e "${RED}✗ No profiles logged in successfully. Exiting.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Completed login for all selected profiles.${RESET}"
unset password

regions=(
    "eu-west-1"
    "eu-central-1"
)

echo ""
echo -e "${BOLD}Updating kubeconfigs...${RESET}"
for region in "${regions[@]}"; do
    for index in "${succeeded_indices[@]}"; do
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
echo -e "${VF_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  💡 ${DIM}All clusters (lower and higher) are restricted to${RESET}"
echo -e "  ${DIM}Vodafone VPN. Whitelist your IP to access them.${RESET}"
echo -e "${VF_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

read -r -p "Do you want to whitelist your IP on EKS clusters? (yes/no): " proceed

if [ "$proceed" == "yes" ]; then
    cloudgate eks-allowip
else
    echo -e "${DIM}Whitelisting skipped.${RESET}"
fi
