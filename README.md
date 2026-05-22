# aws-eks-login

[![Release Workflow](https://github.com/FathAllaTechOps/aws-eks-login/actions/workflows/release.yml/badge.svg)](https://github.com/FathAllaTechOps/aws-eks-login/actions/workflows/release.yml)

Two CLI tools for AWS authentication and EKS cluster IP whitelisting.

| Tool | Purpose |
| --- | --- |
| `aws-login` | Authenticate to AWS accounts via SAML (saml2aws) and update kubeconfigs |
| `eks-allow` | Whitelist your current external IP on EKS cluster `publicAccessCidrs` |

---

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [jq](https://stedolan.github.io/jq/)
- `dig` (pre-installed on macOS)
- For `aws-login`: [saml2aws](https://github.com/Versent/saml2aws)

---

## Installation

### via Homebrew (recommended)

```bash
brew tap FathAllaTechOps/aws-eks-login
brew install aws-eks-login
```

### Manual install

```bash
curl -sSL https://github.com/FathAllaTechOps/aws-eks-login/archive/refs/heads/main.tar.gz | tar -xz
sudo cp aws-eks-login-main/bin/aws-login.sh /usr/local/bin/aws-login
sudo cp aws-eks-login-main/bin/eks-allow.sh /usr/local/bin/eks-allow
sudo chmod +x /usr/local/bin/aws-login /usr/local/bin/eks-allow
```

---

## Upgrade

### via Homebrew

```bash
brew update && brew upgrade aws-eks-login
```

### Manual upgrade

```bash
VERSION="v1.0.0"   # replace with the latest version
curl -sSL "https://github.com/FathAllaTechOps/aws-eks-login/archive/${VERSION}.tar.gz" | tar -xz
sudo cp "aws-eks-login-${VERSION#v}/bin/aws-login.sh" /usr/local/bin/aws-login
sudo cp "aws-eks-login-${VERSION#v}/bin/eks-allow.sh" /usr/local/bin/eks-allow
sudo chmod +x /usr/local/bin/aws-login /usr/local/bin/eks-allow
```

---

## Usage

### `aws-login` — AWS SAML Authentication

**First-time setup:**

```bash
aws-login config
```

**Authenticate and update kubeconfigs:**

```bash
aws-login
```

You will be prompted for your SSO email and password. The script will:

1. Authenticate each selected profile via `saml2aws`
2. Update `~/.kube/config` for all EKS clusters across `eu-west-1` and `eu-central-1`
3. Optionally run `eks-allow` to whitelist your IP on production clusters

**Options:**

```text
aws-login config     Configure AWS profiles
aws-login --help     Show help
aws-login --version  Show version
```

---

### `eks-allow` — EKS IP Whitelisting

Adds your current external IP as a `/32` CIDR to EKS cluster `publicAccessCidrs`.

Supports both **AWS SSO** profiles (`~/.aws/config`) and **static credential** profiles (`~/.aws/credentials`).

```bash
eks-allow
```

You will be prompted to select:

1. AWS region (`eu-west-1`, `eu-central-1`, `us-east-2`, `us-east-1`)
2. AWS profile — SSO profiles are tagged `[sso]`, credential profiles tagged `[creds]`
3. Which clusters to update

If your SSO session is expired, the script automatically triggers `aws sso login` before proceeding.

```text
eks-allow --help     Show help
```

> **Note:** IP whitelisting is only needed for **production accounts**. Lower environments are open to `0.0.0.0/0` by default.

---

## Release process

Releases are published via the [Release Workflow](https://github.com/FathAllaTechOps/aws-eks-login/actions/workflows/release.yml), triggered manually.

**Steps:**

1. Merge all changes into `main`
2. Go to **Actions → Release Workflow → Run workflow**
3. Enter the version in `vX.Y.Z` format (e.g. `v1.1.0`)
4. Click **Run workflow**

The workflow will:

1. Validate the version format
2. Run ShellCheck on all `.sh` files — release is blocked if any check fails
3. Create a GitHub release and upload both scripts as assets
4. Compute the SHA256 checksum and automatically update the Homebrew formula

**Versioning convention:** follow [semver](https://semver.org/).

- Bump **patch** (`v1.0.x`) for bug fixes
- Bump **minor** (`v1.x.0`) for new features or backward-compatible changes
- Bump **major** (`vx.0.0`) for breaking changes

---

## Configuration files

| Path | Purpose |
| --- | --- |
| `~/.aws-eks-login/profiles.config` | Profiles saved by `aws-login config` |
| `~/.aws/config` | AWS SSO profiles |
| `~/.aws/credentials` | Static credential profiles (legacy) |
| `~/.saml2aws` | saml2aws configuration |
