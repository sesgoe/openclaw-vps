# HEY gateway: a restricted HEY CLI for the OpenClaw agent

The OpenClaw agent gets a `hey` command that reads and organizes your HEY mail and calendar
and writes drafts, but cannot send, forward, share or screen. The HEY credentials never
reach the OpenClaw gateway: they live on this separate, disposable Droplet, and the agent
reaches them only through a restricted build of the HEY CLI, over SSH, on the tailnet.

```
OpenClaw gateway                      hey-gateway (this directory)
────────────────                      ─────────────────────────────────────────────
agent runs `hey …`                    sshd, user gordy: ForceCommand, no TTY, no forwarding
  client/hey quotes the args  ─ssh─▶  sudo -u hey /usr/local/libexec/hey-gordy
  ~/.ssh/hey_gateway_gordy    tailnet   splits SSH_ORIGINAL_COMMAND (no shell), enforces
                                        the allowlist, logs argv to /var/log/auth.log
                                      /var/lib/hey/.config/hey-cli/credentials.json (0600, user hey)
```

## What enforces what

HEY's OAuth token has no scopes, and saving a draft and sending one hit the same endpoints,
so **the binary is the boundary**. `hey-gordy` is built from the fork at
`~/personal/forks/hey-cli` (`cmd/hey-gordy`, `internal/cmd/restricted.go`):

- The command tree is pruned to `internal/cmd/restricted.surface`, an allowlist. Anything
  upstream adds is excluded until it is listed there.
- Flags not on the allowlist are refused: no `--attach` (it would read local files — the
  credentials — into a draft), no `--jq`, no `--base-url`, no `--account`.
- `compose` and `reply` always save a draft, whatever flags they get.
- `draft edit`/`delete` only touch drafts `hey-gordy` created, and never a scheduled one
  (HEY sends a scheduled draft by itself).
- Events with guests are never edited or deleted, and `--invite` is gone: HEY emails guests.
  Only writes whose every affected day can be read are allowed: a one-off event (checked on
  every calendar), or one day of a repeating event with `--apply-to current` (that day checked
  on every calendar). Whole-series and `--apply-to future` writes are refused, since any day
  of a series can carry guests of its own on any date.
- Gone entirely: `draft send`, `forward`, `bulk-reply`, `share`, `screener`, `contact
  add/update/deliver` (each can let a sender past the Screener), `auth`, `config`,
  `upgrade`, `watch`, `mcp`, `tui`, `attachment save` (use `attachment get`, which streams
  to stdout).
- Every `HEY_*` variable is dropped, the base URL is pinned to `https://app.hey.com`.

Around it, the host makes sure the binary is the only thing the agent can run: `restrict`
and `command=` on the agent's key, `ForceCommand`, `PermitTTY no` and `DisableForwarding
yes` for `gordy`, and a sudoers rule allowing exactly `hey-gordy` with no arguments as
`hey`. The agent's account owns nothing; the credentials belong to `hey`, which cannot log
in. There is no inbound traffic from the internet: the cloud firewall has no inbound
rules and UFW admits SSH on `tailscale0` only.

All of this was exercised against an Ubuntu 24.04 container: shells, `sh -c`, PTYs, sftp,
port forwarding, `SetEnv`, `--attach`, `--base-url`, `--jq`, `draft send` and hostile
quoting were all refused or inert.

## The short way

```bash
make bring-up
```

`scripts/bring-up.sh` walks through everything below in order, opening the Tailscale,
DigitalOcean and HEY pages when it needs you and doing the rest itself: it builds the
binaries, makes the agent's key on the OpenClaw gateway, applies Terraform, waits for the
bootstrap, deploys, signs in (pasting the callback URL into the wizard, no second
terminal), and installs the client files on the OpenClaw gateway. The DigitalOcean token
and the Tailscale key stay in memory; nothing is saved. Re-running it skips what's already
done. The sections below are the same steps by hand.

## Before the first bring-up

1. **Build the binaries** in the fork (both are needed: `hey-gordy` for the agent, the full
   `hey` only for signing in):

   ```bash
   cd ~/personal/forks/hey-cli && scripts/build-hey-gordy.sh
   ```

2. **Create the agent's SSH key on the OpenClaw gateway**, as the user OpenClaw runs as:

   ```bash
   ssh -i ~/.ssh/openclaw_admin openclaw-admin@openclaw-gateway \
     'ssh-keygen -t ed25519 -a 64 -N "" -C gordy@openclaw-gateway -f ~/.ssh/hey_gateway_gordy && cat ~/.ssh/hey_gateway_gordy.pub'
   ```

   Keep the printed public key; it goes into `TF_VAR_agent_ssh_public_key`.

3. **Generate a one-off Tailscale auth key** carrying `tag:openclaw` (the same tag the
   OpenClaw gateway uses, so no ACL change is needed), as in the top-level README.

## Bring-up

```bash
cd ~/personal/openclaw/hey-cli-ssh

printf 'DigitalOcean token: '; read -rs DIGITALOCEAN_TOKEN; printf '\n'
printf 'Tailscale one-off auth key: '; read -rs TF_VAR_tailscale_auth_key; printf '\n'
export DIGITALOCEAN_TOKEN TF_VAR_tailscale_auth_key
export TF_VAR_ssh_public_key="$(< ~/.ssh/openclaw_admin.pub)"
export TF_VAR_agent_ssh_public_key='ssh-ed25519 AAAA… gordy@openclaw-gateway'

make init
make plan     # read it
make apply
```

Defaults: NYC3, `s-1vcpu-512mb-10gb` (the $4 Droplet; if the region lacks it, use
`s-1vcpu-1gb`), no backups — the only state is the HEY sign-in, and a rebuild just signs in
again. Wait a few minutes for cloud-init, then:

```bash
ssh -i ~/.ssh/openclaw_admin hey-admin@hey-gateway sudo cloud-init status --wait --long
make deploy   # installs hey-gordy
make login    # signs the gateway in to HEY
```

`make login` copies the full `hey` CLI over, runs `hey auth login --no-browser` as the
`hey` user, and deletes the binary afterwards, even if the session drops. Open the printed
URL in your browser and approve. HEY then redirects to `http://127.0.0.1:<port>/callback?…`,
which is the gateway's loopback, not yours, so the page fails to load. Copy that URL and,
in a second terminal:

```bash
make login-callback URL='http://127.0.0.1:…/callback?code=…&state=…'
```

The first terminal then confirms the sign-in and lists the account through `hey-gordy`.

## On the OpenClaw gateway

```bash
ssh -i ~/.ssh/openclaw_admin openclaw-admin@openclaw-gateway 'mkdir -p ~/.local/bin'
scp -i ~/.ssh/openclaw_admin client/hey openclaw-admin@openclaw-gateway:.local/bin/hey
ssh -i ~/.ssh/openclaw_admin openclaw-admin@openclaw-gateway '{ echo; cat; } >> ~/.ssh/config && chmod 600 ~/.ssh/config' < client/ssh_config
ssh -i ~/.ssh/openclaw_admin openclaw-admin@openclaw-gateway '~/.local/bin/hey box view imbox'
```

Make sure `~/.local/bin` is on the PATH the OpenClaw Gateway daemon runs with, or install
the script wherever that PATH looks.

`client/ssh_config` does not pin the host key: Tailscale already authenticates the machine
behind `hey-gateway`, and a pinned key would break on every rebuild. It multiplexes
connections for a minute so a run of commands doesn't reconnect each time.

Give the agent `client/skill/SKILL.md` as its `hey` skill: copy it to
`~/.openclaw/workspace/skills/hey/SKILL.md`, the workspace of OpenClaw's default agent
(`main`), and check with `openclaw skills info hey`. It describes the commands and, as
important, the limits, so the agent reports a refusal instead of hunting for a workaround.

## Updating, rebuilding, tearing down

- **New hey-gordy:** rebuild in the fork, then `make deploy`.
- **Upstream changes:** in the fork, `jj git fetch --remote upstream && jj rebase -d
  main@upstream`, then `scripts/build-hey-gordy.sh` (it runs the restricted tests first).
  `TestRestrictedSurfaceNamesOnlyRealCommandsAndFlags` fails when upstream renames something
  on the allowlist, and nothing new upstream reaches the agent until it is added to
  `restricted.surface`.
- **Teardown:** `make destroy`. Before the next `make apply`, **remove the old
  `hey-gateway` machine in the Tailscale admin console**, or the new one enrolls as
  `hey-gateway-1` and the agent's `ssh_config` points at nothing (`make bring-up` walks
  you through it). The scripts keep the gateway's host key in
  `~/.ssh/known_hosts.hey-gateway`; delete that file after a rebuild if you are not using
  `make bring-up`, which does it for you.
- **Changing the agent's key** changes user data, which replaces the Droplet: sign in again.
- **Audit:** every call is in `/var/log/auth.log` twice — sudo's `COMMAND=` line and
  `hey-gordy`'s `argv=[…]` line (arguments over 120 characters are cut).

## If something goes wrong

If you think the gateway or its credentials are compromised: `make destroy`, delete
`~/.ssh/hey_gateway_gordy*` on the OpenClaw gateway before generating a new key, and revoke
the CLI's sign-in on HEY's side. Where HEY lists signed-in apps or sessions hasn't been
checked yet; find it before you need it.

## Accepted risks

- **A draft you schedule while Gordy is editing it.** `draft edit` checks the draft is
  unscheduled, then the edit reads it again and keeps whatever schedule that read finds. If
  you schedule one of Gordy's drafts in that instant, Gordy's edit goes out on your
  schedule. Closing it would take a conditional write on HEY's side; don't schedule
  Gordy's drafts, or send them directly instead.
- **Resource exhaustion.** Stdin bodies are read without a size limit and there are no
  memory or concurrency caps, so Gordy could exhaust the 512 MB Droplet. That costs
  availability, not credentials or mail: reboot it from the DigitalOcean console.

## Still to verify against the real account

- Whether HEY lists you among an event's `attendances` on an event with no other guests. If
  it does, `hey-gordy` will refuse to edit or delete every event, and the guest check needs to
  skip your own addresses.
- Whether the $4 size is offered in your chosen region.
