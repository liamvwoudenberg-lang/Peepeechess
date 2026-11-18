# Oracle Cloud Always Free deployment of the dedicated server

Nothing here was run against Oracle. Everything is files; no infrastructure exists until **you** enable the workflows below.
Never paste private keys, API keys or tokens into chat, issues or commits: they go only into GitHub Actions secrets.

## What exists

| File | Purpose |
| --- | --- |
| `tools/deploy/build_server.sh <x86_64\|arm64>` | Exports the dedicated server (smoke-tested on x86_64, ELF-checked for arm64). `install_server_templates.sh` fetches the verified export templates. |
| `tools/deploy/remote/bootstrap_vm.sh` | One-time VM setup: service user, directories, systemd unit, env template, OS firewall. |
| `tools/deploy/remote/install_release.sh` | On the VM: install a package, restart, health-check (`SERVER_READY` + UDP socket), **roll back** to the previous release on failure, keep the last 3. |
| `tools/deploy/systemd/peepeechess-server.service`, `server.env.example` | The service (sandboxed, 1 GB memory cap) and its settings template (`/etc/peepeechess/server.env`, mode 600). |
| `.github/workflows/deploy-oracle.yml` | Manual: build both architectures, deploy one over SSH (pinned host key), report failures as an issue. |
| `tools/deploy/oci_provision_a1.sh` + `.github/workflows/oracle-a1-provision.yml` | Hourly, idempotent creation of one Always Free A1 instance. Off until `ORACLE_PROVISION_ENABLED=true`. |
| `tools/deploy/bootstrap-oracle.ps1` | Windows helper: SSH key pair, secrets checklist, optional `gh secret set`. |

## Always Free guard rails (enforced by `oci_provision_a1.sh`)

- The shape is hard-coded to `VM.Standard.A1.Flex`; no other shape can be created.
- Before creating, it sums existing A1 usage and refuses (exit 3, issue "refused") if the total would pass **4 OCPUs, 24 GB memory or 200 GB boot volume**. Defaults: 2 OCPUs, 12 GB, 50 GB.
- It never deletes, stops or edits anything. An existing, non-terminated instance named `peepeechess-a1` means "nothing to do". Your old instance is never touched.
- No load balancer, no extra volumes, no reserved IPs are created.
- "Out of host capacity" is normal for A1: the run ends quietly and the next hourly run retries. After success, later runs report `exists` and create no issues.
- Notifications: a GitHub issue is opened when the instance is created, when provisioning is refused, or on a real error.
- Stop the hourly runs after success: set `ORACLE_PROVISION_ENABLED` to `false` (or delete the variable).

## What you have to do (in order)

1. **Oracle account**: Always Free tier, "Pay As You Go" upgrade is NOT needed and must not be done. Pick a home region with A1 capacity.
2. **Networking (console)**: a VCN with a public subnet and an internet gateway; in the subnet's security list allow ingress **UDP 2456** (game) and **TCP 22** (SSH, ideally restricted to your IP).
3. **Least-privilege API user** (a dedicated group, not the tenancy admin). Policy (replace the names):
   ```
   Allow group peepeechess-deployers to manage instance-family in compartment peepeechess
   Allow group peepeechess-deployers to read virtual-network-family in compartment peepeechess
   Allow group peepeechess-deployers to use subnets in compartment peepeechess
   Allow group peepeechess-deployers to read volume-family in compartment peepeechess
   Allow group peepeechess-deployers to read app-catalog-listing in compartment peepeechess
   ```
   Put the work in its own compartment `peepeechess`. Create an API key for that user (console: User > API keys) and keep the PEM.
4. **SSH key**: on Windows run `powershell -ExecutionPolicy Bypass -File tools\deploy\bootstrap-oracle.ps1` (add `-SetSecrets` to upload the secrets with the GitHub CLI; it asks for each value and never echoes it).
5. **GitHub secrets** (Settings > Secrets and variables > Actions):

   | Secret | Value |
   | --- | --- |
   | `OCI_USER_OCID`, `OCI_TENANCY_OCID`, `OCI_FINGERPRINT`, `OCI_REGION` | from the API key configuration preview |
   | `OCI_API_KEY_PEM` | the private API key (PEM text) |
   | `OCI_COMPARTMENT_OCID`, `OCI_SUBNET_OCID`, `OCI_AVAILABILITY_DOMAIN` | the compartment, the public subnet, the AD name |
   | `OCI_IMAGE_OCID` | an **aarch64** Ubuntu 24.04 image OCID for your region |
   | `ORACLE_SSH_PUBLIC_KEY` / `ORACLE_SSH_PRIVATE_KEY` | the deploy key pair from step 4 |
   | `ORACLE_HOST`, `ORACLE_SSH_USER` | VM public IP (from the "created" issue) and `ubuntu` |
   | `ORACLE_KNOWN_HOSTS` | output of `ssh-keyscan -t ed25519 <ip>` verified once against the console fingerprint |

   Also create a GitHub **environment** `oracle-production` (optionally with yourself as required reviewer).
6. **Provision**: set the repository variable `ORACLE_PROVISION_ENABLED=true` (or run "Oracle A1 provisioning" manually). Wait for the "instance created" issue, then set the variable back to `false`.
7. **Prepare the VM once**: `scp -r tools/deploy ubuntu@<ip>:~/deploy && ssh ubuntu@<ip> 'sudo bash ~/deploy/remote/bootstrap_vm.sh'`, then edit `/etc/peepeechess/server.env` (backend URL, secret) and place the DTLS certificate/key at the paths in that file (a self-signed pair works for testing: `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout server.key -out server.crt -subj /CN=<host>`).
8. **Deploy**: run "Deploy server to Oracle" (arch `arm64` for A1). The log ends with `DEPLOYED <release>` or `ROLLED BACK`.
9. **Point the clients** at `<ip>:2456` (the account backend URL is separate; see `docs/architecture` and the Vercel notes).

## Known limits

- The exported server was only smoke-tested on x86_64; the arm64 binary has never been run (no arm64 machine was available). The first deploy to the A1 is its first real run: check `journalctl -u peepeechess-server`.
- Health check = process active, `SERVER_READY` in the journal, UDP port bound. It does not play a match; run the probe client (`godot/network/server/probe_client.gd`) from your PC against `<ip>:2456` afterwards.
- A1 capacity can take days; the hourly retry is the only mechanism.
