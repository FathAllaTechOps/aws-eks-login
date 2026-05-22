#!/bin/bash

CONFIG_DIR="$HOME/.aws-eks-login"
CONFIG_FILE="$CONFIG_DIR/profiles.config"
VERSION="v1.0.0"

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
Usage: aws-login [OPTION]

Options:
  config             Configure the AWS profiles to use for SAML authentication.
  --help             Display this help message and exit.
  --version          Display version information and exit.

Description:
  Authenticates to multiple AWS accounts using SAML (saml2aws) and updates
  kubeconfig for all EKS clusters in the configured regions.

  After login, optionally runs eks-allow to whitelist your IP on production clusters.

Example:
  aws-login config   # first-time setup
  aws-login          # authenticate and update kubeconfigs

EOF
}

display_version() {
    echo "aws-login $VERSION"
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

if [ "$1" == "config" ]; then
    config_profiles
    exit 0
fi

load_profiles

if [ ${#profiles[@]} -eq 0 ]; then
    echo "No profiles found. Please run 'aws-login config' to configure profiles."
    exit 1
fi

if [ -z "$SAML_EMAIL" ]; then
    read -r -p "Enter the email: " SAML_EMAIL
    export SAML_EMAIL
else
    echo "Email set to: $SAML_EMAIL"
    read -r -p "Press Enter to confirm or enter a new email: " new_email
    if [ -n "$new_email" ]; then
        SAML_EMAIL="$new_email"
        export SAML_EMAIL
    fi
fi

read_password "Enter the password: "

echo "Available AWS Accounts:"
i=1
for profile in "${profiles[@]}"; do
    echo "$i) $profile"
    ((i++))
done

read -r -p "Enter the numbers of the profiles you want to use, separated by commas (e.g., 1,3,5): " selected_profiles

IFS=',' read -ra profile_indices <<< "$selected_profiles"

login_with_profile() {
    local profile=$1
    echo "Replacing aws_profile with '$profile' in ~/.saml2aws"
    sed -i '' '/aws_profile/d' ~/.saml2aws
    echo "aws_profile             = $profile" >> ~/.saml2aws

    echo "Logging in with profile '$profile'"
    saml2aws login --force --username="$SAML_EMAIL" --password="$password" --skip-prompt
    echo "---------------------------------------------"
}

for index in "${profile_indices[@]}"; do
    profile=${profiles[$((index-1))]}
    if [ -n "$profile" ]; then
        login_with_profile "$profile"
    else
        echo "Invalid profile selection: $index. Skipping."
    fi
done

echo "Completed login for all selected profiles."
unset password

regions=(
    "eu-west-1"
    "eu-central-1"
)

for region in "${regions[@]}"; do
    for index in "${profile_indices[@]}"; do
        profile=${profiles[$((index-1))]}
        if [ -n "$profile" ]; then
            clusters=$(aws eks list-clusters --output text --profile "$profile" --region "$region" | awk '{print $2}')
            while read -r cluster; do
                if aws eks update-kubeconfig --region "$region" --name "$cluster" --profile "$profile"; then
                    echo "Updated kubeconfig for cluster $cluster in $region using profile $profile"
                else
                    echo "Failed to update kubeconfig for cluster $cluster in $region using profile $profile"
                fi
            done <<< "$clusters"
        fi
    done
done

echo "############################################################"
echo "#   Note: IP whitelisting is only needed for Production    #"
echo "#   Lower accounts are open to 0.0.0.0/0 by default.      #"
echo "############################################################"

read -r -p "Do you want to whitelist your IP on EKS clusters? (yes/no): " proceed

if [ "$proceed" == "yes" ]; then
    eks-allow
else
    echo "Whitelisting skipped."
fi
