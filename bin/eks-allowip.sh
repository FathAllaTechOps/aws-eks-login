#!/bin/bash

VERSION="v2.8.0"

# Colors — Vodafone brand palette
VF_RED='\033[38;2;230;0;0m'    # Vodafone Red #E60000
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

show_help() {
  echo "Usage: cloudgate eks-allowip [options]"
  echo ""
  echo "Options:"
  echo "  --help             Display this help message"
  echo "  --version          Display version information"
  echo "  --show-commands    Show available commands"
  echo ""
  echo "Whitelists your current external IP on EKS cluster publicAccessCidrs."
  echo "Supports SAML and SSO credential profiles."
}

show_commands() {
  cat <<EOF
cloudgate available commands:

  cloudgate saml                         AWS SAML login (saml2aws)
  cloudgate saml config                  Configure AWS profiles
  cloudgate eks-allowip                  Whitelist your IP on EKS clusters
  cloudgate eks-allowip --help           Show help
  cloudgate eks-allowip --version        Show version
  cloudgate eks-allowip --show-commands  Show this command list
  cloudgate status                       Show session status for all profiles
  cloudgate --show-commands              Show all cloudgate commands

EOF
}

if [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ "$1" == "--version" ]]; then
  echo "cloudgate eks-allowip $VERSION"
  exit 0
fi

if [[ "$1" == "--show-commands" ]]; then
  show_commands
  exit 0
fi

# Fixed CIDRs always included in publicAccessCidrs
fixed_cidrs=(
  "213.30.78.168/32"
  "194.62.232.104/32"
  "213.30.78.170/32"
  "213.30.78.172/32"
  "85.115.52.0/24"
  "194.62.232.102/32"
  "81.12.134.72/32"
  "46.97.128.35/32"
  "85.115.53.0/24"
  "85.115.49.0/24"
  "195.233.26.80/28"
  "81.12.134.71/32"
  "94.62.209.237/32"
  "194.62.232.110/32"
  "102.221.68.0/22"
  "178.166.3.30/32"
  "41.235.102.159/32"
  "194.62.232.103/32"
  "157.167.71.0/24"
  "62.68.247.20/32"
  "213.30.78.169/32"
  "194.62.232.109/32"
  "213.30.78.171/32"
  "185.4.97.2/32"
  "212.18.162.33/32"
  "194.62.232.101/32"
  "85.115.54.0/24"
  "81.12.134.70/32"
  "185.4.96.2/32"
  "192.151.176.2/32"
  "41.235.14.181/32"
  "87.75.68.116/32"
  "85.115.50.2/32"
  "195.233.26.0/24"
  "102.221.68.0/24"
)

get_config_profiles() {
  if [ ! -f ~/.aws/config ]; then return; fi
  grep '^\[profile ' ~/.aws/config | sed 's/^\[profile //;s/\]$//' | while read -r profile; do
    local block
    block=$(grep -A 20 "^\[profile $profile\]" ~/.aws/config)
    if echo "$block" | grep -q 'sso_start_url'; then
      echo "$profile [sso]"
    fi
  done
}

get_credential_profiles() {
  if [ ! -f ~/.aws/credentials ]; then return; fi
  grep '^\[.*\]$' ~/.aws/credentials | tr -d '[]' | while read -r profile; do
    echo "$profile [saml]"
  done
}

ensure_session() {
  local profile=$1
  local profile_type=$2
  if ! aws sts get-caller-identity --profile "$profile" > /dev/null 2>&1; then
    if [[ "$profile_type" == "sso" ]]; then
      echo -e "${YELLOW}⚠ SSO session expired for '$profile'. Launching browser login...${RESET}"
      aws sso login --profile "$profile"
    else
      echo -e "${RED}✗ Credentials expired for profile '$profile'. Run 'cloudgate saml' to re-authenticate.${RESET}"
      exit 1
    fi
  fi
}

echo ""
echo -e "${BOLD}Choose the AWS region:${RESET}"
PS3=$'\n'"Region #? "
options=("eu-west-1" "eu-west-2" "eu-central-1" "us-east-2" "us-east-1")
select aws_region in "${options[@]}"; do
  for option in "${options[@]}"; do
    if [[ "$aws_region" == "$option" ]]; then
      valid=true
      break
    fi
  done
  if [ "$valid" ]; then
    break
  else
    echo -e "${RED}Invalid selection. Please choose a valid AWS region.${RESET}"
  fi
done
echo -e "${DIM}Selected region: ${VF_RED}$aws_region${RESET}"

all_profiles=()
while IFS= read -r line; do
  all_profiles+=("$line")
done < <({ get_config_profiles; get_credential_profiles; })

if [ ${#all_profiles[@]} -eq 0 ]; then
  echo -e "${RED}✗ No AWS profiles found. Authenticate first using 'cloudgate saml'.${RESET}"
  exit 1
fi

echo ""
echo -e "${BOLD}Available AWS profiles:${RESET}"
PS3=$'\n'"Profile #? "
select entry in "${all_profiles[@]}"; do
  if [ -n "$entry" ]; then
    break
  else
    echo -e "${RED}Invalid selection. Please choose a valid profile.${RESET}"
  fi
done
echo -e "${DIM}Selected profile: ${VF_RED}$entry${RESET}"

aws_profile="${entry% \[*\]}"
if [[ "$entry" == *"[sso]"* ]]; then
  profile_type="sso"
else
  profile_type="saml"
fi

ensure_session "$aws_profile" "$profile_type"

echo ""
echo -e "${DIM}Fetching clusters in ${VF_RED}$aws_region${DIM}...${RESET}"
clusters=$(aws eks list-clusters --region "$aws_region" --profile "$aws_profile" | jq -r '.clusters[]')

if [ -z "$clusters" ]; then
  echo -e "${RED}✗ No EKS clusters found in region '$aws_region'.${RESET}"
  exit 1
fi

echo ""
echo -e "${BOLD}Available EKS clusters in ${VF_RED}$aws_region${RESET}${BOLD}:${RESET}"
i=1
for cluster in $clusters; do
  echo -e "  ${VF_RED}$i)${RESET} ${BOLD}$cluster${RESET}"
  ((i++))
done

read -r -p "$(echo -e "\nEnter cluster numbers (e.g., 1,2): ")" selected_clusters

read -r -p "$(echo -e "\n${YELLOW}Whitelist your IP on selected clusters in '${aws_region}'? (y/n):${RESET} ")" confirm
if [ "$confirm" != "y" ]; then
  echo -e "${DIM}Operation canceled.${RESET}"
  exit 1
fi

# Detect personal IP
echo ""
externalIp=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
personalCidr="$externalIp/32"
echo -e "🌐 ${BOLD}Your current IP:${RESET} ${VF_RED}$personalCidr${RESET}"

MAX_CIDRS=40

IFS=',' read -ra cluster_indices <<< "$selected_clusters"
for index in "${cluster_indices[@]}"; do
  cluster_name=$(echo "$clusters" | sed -n "${index}p")
  if [ -z "$cluster_name" ]; then
    echo -e "${RED}✗ Invalid cluster selection: $index. Skipping.${RESET}"
    continue
  fi

  # Get current CIDRs on the cluster
  currentCidrs=$(aws eks describe-cluster --name "$cluster_name" --region "$aws_region" --profile "$aws_profile" \
    | jq -r '.cluster.resourcesVpcConfig.publicAccessCidrs[]')

  # Check if personal IP is already whitelisted
  if echo "$currentCidrs" | grep -qx "$personalCidr"; then
    echo -e "  ${DIM}$cluster_name: $personalCidr already whitelisted. Skipping.${RESET}"
    continue
  fi

  currentCount=$(echo "$currentCidrs" | grep -c '.' || true)
  newCount=$((currentCount + 1))

  if [ "$newCount" -le "$MAX_CIDRS" ]; then
    updatedCidrs=$(printf '%s\n' "$currentCidrs" "$personalCidr" | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')
    echo -e "  ${VF_RED}↑${RESET} ${BOLD}$cluster_name${RESET}${DIM}: appending $personalCidr ($newCount/$MAX_CIDRS CIDRs)${RESET}"
  else
    echo -e "  ${YELLOW}⚠${RESET} ${BOLD}$cluster_name${RESET}${DIM}: limit reached ($currentCount/$MAX_CIDRS). Resetting to fixed IPs + $personalCidr.${RESET}"
    reset_cidrs=("${fixed_cidrs[@]}" "$personalCidr")
    updatedCidrs=$(printf '%s\n' "${reset_cidrs[@]}" | sort -u | tr '\n' ',' | sed 's/,$//')
  fi

  aws eks update-cluster-config --name "$cluster_name" --region "$aws_region" \
    --resources-vpc-config publicAccessCidrs="$updatedCidrs" --profile "$aws_profile" > /dev/null 2>&1

  echo -e "  ${GREEN}✓${RESET} ${BOLD}$cluster_name${RESET} updated in ${VF_RED}$aws_region${RESET}"
done

echo ""
echo -e "${GREEN}✓ Operation completed.${RESET}"
