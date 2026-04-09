# Deploying new turnkey stack

> **Using turnkey in your organisation?** Do not fork — use it as a GitHub template. See [Using turnkey as a Template](#using-turnkey-as-a-template) below.

## Using turnkey as a Template

Turnkey is designed to be adopted via GitHub's **"Use this template"** feature, not forked. This gives you a clean, independent repo (no upstream link, private from creation) that you own and customise freely.

### 1. Create your repo from the template

On GitHub, click **"Use this template" → "Create a new repository"**. Choose a name, set visibility to **Private**, and create it.

### 2. Set your repo URL

Every stack config in `stacks/` and `pulumi/Pulumi.*.yaml` has a single line to change:

```yaml
argocd.repoUrl: https://github.com/your-org/your-repo
```

This value controls everything: where ArgoCD pulls from, which source repo the `platform` AppProject trusts, and what gets referenced in change-control annotations. It is the only URL you need to update.

### 3. Customise your stacks

Edit the stack configs under `stacks/` for your environments (cluster size, region, feature flags, etc.). The rest of the platform picks up from there.

### 4. Bootstrap

Follow the normal bootstrap procedure in [docs/runbooks/bootstrap.md](docs/runbooks/bootstrap.md).

### Staying up to date with upstream

Since your repo has no upstream link, pull upstream changes manually:

```bash
git remote add upstream https://github.com/EpykLab/turnkey
git fetch upstream
git merge upstream/master
```

Review the diff carefully before merging — upstream changes may conflict with your customisations.

## Deployment steps

### Install prerequisits

1. Golang
2. Kubectl
3. Pulumi
4. Task

Depending on your secrets backend, you may need to have
one of the following:

1. 1password-cli
2. Az-cli
3. Doppler-cli

Depending on your platform you may need to install these
via different means.

### Init the stack

Turnkey ships with a `Taskfile.yaml` file that contains many
helpers for deploying and managing the stack. The following should be executed in order.

1. `task pulumi:stack:init`: This will init a new stack and ask for a password
   to be used to encrypt local state
2. `task deploy`: This will deploy the new stack
3. After some time we can use `task status` to check and
