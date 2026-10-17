# OpenClaw gateway infrastructure

**The gateway no longer runs on the Droplet below.** `infra/` is kept for reference and as a rollback; `hey-cli-ssh/`
is unchanged and still in use. `scripts/install-openclaw.sh` also supports Ubuntu 26.04.

This repository provisions a hardened Ubuntu 24.04 DigitalOcean Droplet, enrolls it in Tailscale during first boot, and leaves OpenClaw itself for a separate, interactive setup step. There is no temporary public SSH phase.

## Architecture

The Droplet has a public IPv4 address for direct outbound internet access, but DigitalOcean's stateful cloud firewall has zero inbound rules. UFW also denies public ingress. Tailscale starts from an outbound connection and remains reachable through its encrypted tailnet, using DERP relays when a direct path is unavailable.

The setup creates a dedicated VPC, an attach-by-tag cloud firewall before the Droplet, weekly backups, free enhanced monitoring, a non-root administrator, key-only SSH, unattended security updates, and a host firewall that only accepts SSH on `tailscale0`.

## Before applying

1. Install Terraform 1.10 or newer. This workspace already has a suitable version.
2. Have an Ed25519 SSH key. Generate a dedicated one if needed:

   ```bash
   ssh-keygen -t ed25519 -a 64 -f ~/.ssh/openclaw_admin -C openclaw-admin
   ```

3. In Tailscale's **Access controls** editor, add `tag:openclaw` to `tagOwners`, using your exact Tailscale login identity. Keep the default allow-all grant; no groups or additional grants are needed:

   ```jsonc
   "tagOwners": {
     "tag:openclaw": ["you@example.com"],
   },
   ```

4. Open **Settings → Keys** and generate a **one-off** auth key carrying `tag:openclaw`. Leave **Reusable** and **Ephemeral** off. Leave **Pre-approved** off unless you have separately enabled device approval. A one-off key is automatically revoked after the Droplet uses it.
5. Prefer replacing the full-access DigitalOcean token with a short-lived or narrowly scoped infrastructure token once the first deployment is working. Never paste either token into a tracked file or chat.

Read credentials silently into the current shell so they do not enter shell history:

```bash
printf 'DigitalOcean token: '
read -rs DIGITALOCEAN_TOKEN
printf '\nTailscale one-off auth key: '
read -rs TF_VAR_tailscale_auth_key
printf '\n'
export DIGITALOCEAN_TOKEN TF_VAR_tailscale_auth_key
export TF_VAR_ssh_public_key="$(< ~/.ssh/openclaw_admin.pub)"
```

The Tailscale key necessarily passes through Droplet user data and local Terraform state. Using a one-off key makes it unusable immediately after enrollment. Terraform marks the value sensitive, and `.gitignore` excludes state and variable files; still protect and eventually move state to an encrypted remote backend before collaborating with others.

## Review and apply

The defaults use NYC3, a 2 vCPU / 4 GiB Ubuntu 24.04 Droplet, weekly backups, and firewalled public networking. The additional memory and CPU provide headroom for Chromium-heavy OpenClaw workloads. Put only non-secret overrides in `infra/terraform.tfvars` (start from `infra/terraform.tfvars.example`).

```bash
make init
make fmt
make validate
make plan
make apply
```

Always read the saved plan before applying, especially the Droplet size and estimated monthly resources. `make apply` only consumes that saved plan so the reviewed plan and applied plan cannot silently diverge. The wrapper creates the plan with owner-only permissions and deletes it after a successful apply because it contains sensitive bootstrap data.

## Verify the bootstrap

Wait a few minutes for package upgrades and Tailscale enrollment, then from a device on the same tailnet:

```bash
ssh openclaw-admin@openclaw-gateway
sudo cloud-init status --wait --long
sudo test -f /var/lib/openclaw-bootstrap-complete
tailscale status
sudo ufw status verbose
```

In Tailscale's **Machines** page, confirm `openclaw-gateway` is managed by `tag:openclaw`. Tagged machines have node-key expiry disabled by default. No groups, extra grants, device approval, or HTTPS settings are required. Any of your devices signed into the same tailnet can connect under the default allow-all policy.

If bootstrap fails before Tailscale joins, use DigitalOcean's authenticated web console/agent as the recovery path. Do not add a public SSH rule as a first response.

## Next: install OpenClaw

The intended next stage is a native, non-root OpenClaw install owned by `openclaw-admin`. The first-install script explicitly installs Node.js 26, Google Chrome, OpenClaw, useful native build/media tools, and the user-session support needed by the Gateway daemon. It also enables systemd user lingering so the Gateway can survive logout and start at boot. It uses the real Google Chrome Debian package because Ubuntu's `chromium` package is a Snap wrapper that can interfere with OpenClaw-managed browser processes. For npm 11.16 and newer, it permits only OpenClaw's own package lifecycle scripts with `--allow-scripts=openclaw`.

Copy the script to the Droplet and run it as `openclaw-admin` (not with `sudo`; the script prompts for sudo only for system packages):

```bash
scp -i ~/.ssh/openclaw_admin scripts/install-openclaw.sh openclaw-admin@openclaw-gateway:/tmp/
ssh -t -i ~/.ssh/openclaw_admin openclaw-admin@openclaw-gateway \
  'bash /tmp/install-openclaw.sh'
```

The script is designed to be rerun: APT converges system packages, and already-current Chrome and OpenClaw installs are skipped. By default it installs the current `openclaw@latest`, which is convenient but not a bit-for-bit reproducible version. To reproduce a known release, pass its npm version:

```bash
ssh -t -i ~/.ssh/openclaw_admin openclaw-admin@openclaw-gateway \
  'bash /tmp/install-openclaw.sh 2026.7.1-2'
```

The script does not install Docker, modify the firewall, configure providers, or store messaging credentials. Docker can be added later if agent sandboxing is enabled, with its firewall behavior reviewed separately.

If the installation summary reports `Reboot: required`, reboot before onboarding, wait for Tailscale to reconnect, and start a new SSH session:

```bash
sudo reboot
```

After installation, SSH into the Droplet and complete the secret-bearing setup interactively:

```bash
openclaw onboard --install-daemon
```

During onboarding, keep this deployment model:

- Choose local Gateway mode and a loopback bind.
- Keep Gateway token authentication enabled, even on loopback.
- Do not enable OpenClaw's Tailscale exposure; administration already travels over Tailscale and the dashboard uses an SSH tunnel.
- Choose npm when asked for the Node package manager.
- Enter provider and Telegram credentials only in the interactive wizard, never in Terraform variables or this repository.

When using ChatGPT/Codex OAuth rather than an OpenAI Platform API key, make the Codex runtime an explicit, fail-closed requirement. This prevents OpenClaw from falling back to a direct API request that OAuth cannot authenticate:

```bash
openclaw config set models.providers.openai.agentRuntime.id codex
```

After onboarding, configure and verify the managed browser and restart the Gateway:

```bash
openclaw config set browser.executablePath /usr/bin/google-chrome-stable
openclaw config set browser.headless true
openclaw gateway restart
openclaw gateway status
openclaw doctor
```

The script intentionally leaves Chrome's sandbox enabled. Do not set `browser.noSandbox` unless a specific launch failure requires it and the security tradeoff has been reviewed. `openclaw doctor` may identify additional dependencies for optional skills selected during onboarding; those are workload-specific and do not belong in the base host install.

Keep the Gateway bound to loopback. For private dashboard access, forward its loopback port through SSH over Tailscale:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw-admin@openclaw-gateway
```

Then open `http://127.0.0.1:18789/` locally. Tailscale Serve can be added later, but it is not required. OpenClaw's onboarding remains interactive because it collects model-provider and messaging-channel credentials that should not enter Terraform state.

After onboarding, run `openclaw security audit`. Before treating the Gateway as durable, also test restoring its state from a backup.

## HEY access for the agent

`hey-cli-ssh/` provisions a second, disposable Droplet that holds the HEY credentials and gives the agent a restricted `hey` command over SSH: it reads and organizes mail and writes drafts, but cannot send. See `hey-cli-ssh/README.md`.

## Recovery and lifecycle notes

- The Droplet is stateful. Terraform can recreate infrastructure, but only tested backups can restore gateway state and workspaces.
- Powering off a Droplet does not stop billing; destroying it does. The repository intentionally does not wrap `terraform destroy` in a convenience target.
- A second firewall attached later can broaden access because DigitalOcean combines allowed rules. Review all firewalls associated with the Droplet/tag.
- Changing user data, the SSH key, image, or public-networking mode replaces the Droplet. Read every plan before applying.
