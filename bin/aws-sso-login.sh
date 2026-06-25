#!/bin/bash

CONFIG_DIR="$HOME/.cloudgate"
CONFIG_FILE="$CONFIG_DIR/sso-profiles.config"
VERSION="v1.0.0"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        profiles=()
        sso_url=""
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    {
        echo "sso_url=\"$sso_url\""
        echo "profiles=("
        for profile in "${profiles[@]}"; do
            echo "    \"$profile\""
        done
        echo ")"
    } > "$CONFIG_FILE"
}

config_profiles() {
    load_config

    read -r -p "Microsoft SSO URL [${sso_url:-none}]: " input_url
    if [ -n "$input_url" ]; then
        sso_url="$input_url"
    fi

    if [ -z "$sso_url" ]; then
        echo "SSO URL is required."
        exit 1
    fi

    echo "Enter the AWS profile names (one per line). Enter an empty line to finish:"
    echo "(These are the --profile names credentials will be saved under, e.g. dcaas, dmmsandbox)"
    profiles=()
    while :; do
        read -r -p "Profile: " profile
        [ -z "$profile" ] && break
        profiles+=("$profile")
    done

    if [ ${#profiles[@]} -eq 0 ]; then
        echo "No profiles entered. Nothing saved."
        exit 1
    fi

    save_config
    echo "Config saved to $CONFIG_FILE"
}

display_help() {
    cat <<EOF
Usage: aws-sso-login [OPTION]

Options:
  config                Configure the Microsoft SSO URL and AWS profiles.
  --help                Display this help message and exit.
  --version             Display version information and exit.
  --show-commands       Show available commands and exit.

Description:
  Opens your Microsoft SSO URL so you're signed in, then for each selected
  profile runs 'aws login' and automatically selects the matching AWS account's
  DevOps role in the browser using AppleScript.

  After login, optionally runs eks-allowip to whitelist your IP on production clusters.

  Note: On first run, macOS may ask for Accessibility or Automation permissions
  for Terminal to control your browser. Grant them when prompted.

Example:
  aws-sso-login config   # first-time setup
  aws-sso-login          # authenticate and update kubeconfigs

EOF
}

display_commands() {
    cat <<EOF
Available commands:

  aws-sso-login                   Login via browser-based AWS SSO (aws login)
  aws-sso-login config            Configure Microsoft SSO URL and AWS profiles
  aws-sso-login --help            Display help message
  aws-sso-login --version         Display version information
  aws-sso-login --show-commands   Show this command list

  aws-login                       Login via SAML (saml2aws)
  aws-login config                Configure AWS profiles for SAML
  aws-login --help                Display help message
  aws-login --version             Display version information
  aws-login --show-commands       Show this command list

  eks-allowip                     Whitelist your IP on EKS cluster publicAccessCidrs
  eks-allowip --help              Display help message
  eks-allowip --version           Display version information
  eks-allowip --show-commands     Show this command list

EOF
}

display_version() {
    echo "aws-sso-login $VERSION"
}

is_session_valid() {
    local profile=$1
    aws sts get-caller-identity --profile "$profile" > /dev/null 2>&1
}

# Injects JavaScript into the AWS sign-in browser tab that polls for the role
# selection page, finds the radio button for the given account name, clicks it,
# then submits the form. Tries Chrome then Safari. Returns "ok" or "timeout".
automate_browser_login() {
    local account_name="$1"
    local tmpscript
    tmpscript=$(mktemp /tmp/aws-auto-XXXXXX.applescript)

    cat > "$tmpscript" << 'APPLESCRIPT'
on run argv
    set acctName to item 1 of argv

    -- JS: poll every 500ms for radio buttons, click the one whose context
    -- contains the account name, then submit the form.
    set theJS to "(function(n){var a=0,iv=setInterval(function(){a++;var rs=document.querySelectorAll('input[type=radio]');if(rs.length>0){clearInterval(iv);for(var i=0;i<rs.length;i++){var r=rs[i],c=r.parentElement;for(var j=0;j<8&&c;j++){if(c.textContent.indexOf(n)!==-1){r.click();setTimeout(function(){var b=document.getElementById('signin_button')||document.querySelector('button[type=submit]')||document.querySelector('input[type=submit]');if(b)b.click();},500);return;}c=c.parentElement;}}}if(a>=20)clearInterval(iv);},500);})('" & acctName & "')"

    repeat with i from 1 to 30
        delay 1
        -- Try Google Chrome
        try
            if application "Google Chrome" is running then
                tell application "Google Chrome"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "signin.aws.amazon.com" then
                                execute t javascript theJS
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end tell
            end if
        end try
        -- Try Safari
        try
            if application "Safari" is running then
                tell application "Safari"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "signin.aws.amazon.com" then
                                do JavaScript theJS in t
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end tell
            end if
        end try
    end repeat
    return "timeout"
end run
APPLESCRIPT

    local result
    result=$(osascript "$tmpscript" "$account_name" 2>/dev/null)
    rm -f "$tmpscript"
    echo "$result"
}

login_with_profile() {
    local profile=$1

    if is_session_valid "$profile"; then
        echo "Session for '$profile' is already active. Skipping login."
        echo "---------------------------------------------"
        return 0
    fi

    echo "Logging in with profile '$profile'..."
    aws login --profile "$profile" --region eu-west-1 > /dev/null 2>&1 &
    local pid=$!

    sleep 4  # Give the browser time to open the sign-in tab

    echo "  Auto-selecting DevOps role for '$profile'..."
    local result
    result=$(automate_browser_login "$profile")

    if [ "$result" = "ok" ]; then
        echo "  Role selected automatically."
    else
        echo "  Auto-select $result — please manually select the DevOps role for '$profile'."
    fi

    wait "$pid"

    if is_session_valid "$profile"; then
        echo "  Successfully logged in with profile '$profile'."
    else
        echo "  Login failed for profile '$profile'. Skipping."
        echo "---------------------------------------------"
        return 1
    fi
    echo "---------------------------------------------"
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

load_config

if [ -z "$sso_url" ]; then
    echo "No SSO URL configured. Please run 'aws-sso-login config' first."
    exit 1
fi

if [ ${#profiles[@]} -eq 0 ]; then
    echo "No profiles found. Please run 'aws-sso-login config' to configure profiles."
    exit 1
fi

echo "Available AWS Accounts:"
i=1
for profile in "${profiles[@]}"; do
    echo "$i) $profile"
    ((i++))
done

read -r -p "Enter the numbers of the profiles you want to use, separated by commas (e.g., 1,3,5): " selected_profiles

IFS=',' read -ra profile_indices <<< "$selected_profiles"

# Separate already-valid sessions from ones that need login
profiles_to_login=()
logged_in_profiles=()
for index in "${profile_indices[@]}"; do
    profile="${profiles[$((index-1))]}"
    if [ -z "$profile" ]; then
        echo "Invalid profile selection: $index. Skipping."
        continue
    fi
    if is_session_valid "$profile"; then
        echo "Session for '$profile' is already active. Skipping login."
        logged_in_profiles+=("$profile")
    else
        profiles_to_login+=("$profile")
    fi
done

if [ ${#profiles_to_login[@]} -gt 0 ]; then
    echo ""
    echo "Step 1: Sign in via your Microsoft SSO page."
    echo "Opening: $sso_url"
    open "$sso_url"
    read -r -p "Press Enter once you're signed in and can see your AWS accounts in the browser..."
    echo ""

    for profile in "${profiles_to_login[@]}"; do
        if login_with_profile "$profile"; then
            logged_in_profiles+=("$profile")
        fi
    done
fi

if [ ${#logged_in_profiles[@]} -eq 0 ]; then
    echo "No profiles were successfully authenticated. Exiting."
    exit 1
fi

echo "Completed login for all selected profiles."
echo ""

regions=(
    "eu-west-1"
    "eu-central-1"
)

for region in "${regions[@]}"; do
    for profile in "${logged_in_profiles[@]}"; do
        clusters=$(aws eks list-clusters --output text --profile "$profile" --region "$region" 2>/dev/null | awk '{print $2}')
        while read -r cluster; do
            [ -z "$cluster" ] && continue
            if aws eks update-kubeconfig --region "$region" --name "$cluster" --profile "$profile"; then
                echo "Updated kubeconfig for cluster $cluster in $region using profile $profile"
            else
                echo "Failed to update kubeconfig for cluster $cluster in $region using profile $profile"
            fi
        done <<< "$clusters"
    done
done

echo "############################################################"
echo "#   Note: IP whitelisting is only needed for Production    #"
echo "#   Lower accounts are open to 0.0.0.0/0 by default.      #"
echo "############################################################"

read -r -p "Do you want to whitelist your IP on EKS clusters? (yes/no): " proceed

if [ "$proceed" == "yes" ]; then
    eks-allowip
else
    echo "Whitelisting skipped."
fi
