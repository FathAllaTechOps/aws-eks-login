# cloudgate

[![Release Workflow](https://github.com/FathAllaTechOps/cloudgate/actions/workflows/release.yml/badge.svg)](https://github.com/FathAllaTechOps/cloudgate/actions/workflows/release.yml)
[![GitHub Downloads](https://img.shields.io/github/downloads/FathAllaTechOps/cloudgate/total)](https://github.com/FathAllaTechOps/cloudgate/releases)
[![Latest Release](https://img.shields.io/github/v/release/FathAllaTechOps/cloudgate)](https://github.com/FathAllaTechOps/cloudgate/releases/latest)

`cloudgate` is a CLI toolkit for AWS authentication and EKS cluster IP whitelisting.

```text
cloudgate saml          → login to AWS via SAML (saml2aws)
cloudgate eks-allowip   → whitelist your IP on EKS clusters
```

---

## Prerequisites

### macOS

| Dependency | Required by | Install |
| --- | --- | --- |
| AWS CLI v2 | all commands | `brew install awscli` |
| jq | `eks-allowip` | `brew install jq` |
| saml2aws | `saml` | `brew install saml2aws` |
| dig | `eks-allowip` | pre-installed on macOS |

### Linux

| Dependency | Required by | Install |
| --- | --- | --- |
| AWS CLI v2 | all commands | [AWS install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| jq | `eks-allowip` | `sudo apt-get install -y jq` |
| dig | `eks-allowip` | `sudo apt-get install -y dnsutils` |
| saml2aws | `saml` | See below |

**saml2aws on Linux** (no apt package — install from GitHub releases):

```bash
VERSION="2.36.16"  # check latest at github.com/Versent/saml2aws/releases
curl -sSL "https://github.com/Versent/saml2aws/releases/download/v${VERSION}/saml2aws_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin
chmod +x /usr/local/bin/saml2aws
```

> `cloudgate` checks for required dependencies before running each subcommand and prints an install hint if anything is missing.

---

## Installation

### macOS — via Homebrew (recommended)

```bash
brew tap FathAllaTechOps/cloudgate
brew install cloudgate
```

> **Note:** Homebrew requires a separate tap repository (`homebrew-cloudgate`) to host the formula. This is a Homebrew convention — `brew tap FathAllaTechOps/cloudgate` maps to the `homebrew-cloudgate` repo automatically.

### Linux — manual install

```bash
VERSION="v1.3.0"  # replace with the latest version from github.com/FathAllaTechOps/cloudgate/releases
curl -sSL "https://github.com/FathAllaTechOps/cloudgate/archive/${VERSION}.tar.gz" | tar -xz
cd "cloudgate-${VERSION#v}"
sudo cp bin/cloudgate.sh   /usr/local/bin/cloudgate
sudo cp bin/aws-login.sh   /usr/local/bin/aws-login
sudo cp bin/eks-allowip.sh /usr/local/bin/eks-allowip
sudo chmod +x /usr/local/bin/cloudgate /usr/local/bin/aws-login /usr/local/bin/eks-allowip
```

> `aws-login` and `eks-allowip` must be installed alongside `cloudgate` — they are the underlying scripts that `cloudgate saml` and `cloudgate eks-allowip` delegate to.

---

## Upgrade

### macOS — via Homebrew

```bash
brew update && brew upgrade cloudgate
```

### Linux — manual upgrade

Repeat the same steps as the manual install above with the new version number.

---

## Usage

### Quick reference

```bash
cloudgate --help             # show help
cloudgate --version          # show version
cloudgate --show-commands    # list all available commands
```

---

### `cloudgate saml` — AWS SAML Authentication

Authenticates to one or more AWS accounts using SAML via `saml2aws` and updates `~/.kube/config` for all EKS clusters.

**First-time setup:**

```bash
cloudgate saml config
```

You will be prompted to enter your AWS profile names one by one. These are the profile names from your `~/.saml2aws` or `~/.aws/credentials` file.

```text
Enter the AWS profiles (one per line). Enter an empty line to finish:
Profile: dcaas
Profile: maac-stage
Profile: dmmsandbox
Profile:
Profiles saved to ~/.cloudgate/profiles.config
```

To review what you configured:

```bash
cloudgate saml config --list
```

```text
Configured AWS profiles:
  - dcaas
  - maac-stage
  - dmmsandbox
```

**Authenticate and update kubeconfigs:**

```bash
cloudgate saml
```

On first run you will be asked for your SSO email and password. Both can be saved for future runs — email is stored in `~/.cloudgate/config` and the password is stored securely in the system keychain (macOS Keychain or Linux secret-tool).

The command will:

1. Authenticate each selected profile via `saml2aws`
2. Update `~/.kube/config` for all EKS clusters in `eu-west-1` and `eu-central-1`
3. Optionally run `eks-allowip` to whitelist your IP on production clusters

To clear a saved password:

```bash
cloudgate saml --forget-password
```

**All options:**

```text
cloudgate saml                      Run the SAML login wizard
cloudgate saml config               Configure AWS profiles
cloudgate saml config --list        List configured profiles
cloudgate saml --forget-password    Remove saved password from keychain
cloudgate saml --help               Show help
cloudgate saml --version            Show version
cloudgate saml --show-commands      Show all available commands
```

---

### `cloudgate eks-allowip` — EKS IP Whitelisting

Whitelists your current external IP on EKS cluster `publicAccessCidrs`.

```bash
cloudgate eks-allowip
```

You will be prompted to select:

1. AWS region (`eu-west-1`, `eu-central-1`, `us-east-2`, `us-east-1`)
2. AWS profile — `[aws-login]`, `[sso]`, and `[creds]` profiles are all supported
3. Which clusters to update

**How IPs are managed:**

- A set of fixed corporate CIDRs is always maintained on every cluster.
- Your personal external IP (`/32`) is detected and added at runtime.
- If the cluster is **under the 40 CIDR limit** (AWS maximum), your IP is appended — preserving other team members' IPs.
- If adding your IP **would exceed the limit**, the list resets to the fixed corporate CIDRs plus your IP.

**All options:**

```text
cloudgate eks-allowip                  Run the IP whitelisting wizard
cloudgate eks-allowip --help           Show help
cloudgate eks-allowip --version        Show version
cloudgate eks-allowip --show-commands  Show all available commands
```

> **Note:** IP whitelisting is only needed for **production accounts**. Lower environments are open to `0.0.0.0/0` by default.

---

## Configuration files

| Path | Purpose |
| --- | --- |
| `~/.cloudgate/profiles.config` | AWS profiles configured via `cloudgate saml config` |
| `~/.saml2aws` | saml2aws configuration (IDP URL, region, etc.) |
| `~/.aws/config` | AWS SSO profiles |
| `~/.aws/credentials` | Static credential profiles |

---

## Release process

Releases are published via the [Release Workflow](https://github.com/FathAllaTechOps/cloudgate/actions/workflows/release.yml), triggered manually.

**Steps:**

1. Merge all changes into `main`
2. Go to **Actions → Release Workflow → Run workflow**
3. Enter the version in `vX.Y.Z` format (e.g. `v1.4.0`)
4. Click **Run workflow**

The workflow will:

1. Validate the version format
2. Run ShellCheck on all `.sh` files — release is blocked if any check fails
3. Create a GitHub release and upload all scripts as assets
4. Compute the SHA256 checksum and automatically update the Homebrew formula in `homebrew-cloudgate`

**Versioning convention:** follow [semver](https://semver.org/).

- Bump **patch** (`v1.x.Z`) for bug fixes
- Bump **minor** (`v1.Y.0`) for new features or backward-compatible changes
- Bump **major** (`vX.0.0`) for breaking changes
