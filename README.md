#  Internal Monitoring and Observability Platform

## 1. Project Summary

An internal monitoring and observability platform for infrastructure, built on Prometheus and Grafana and running on Microsoft Azure.

The entire environment is defined as code. Terraform creates the Azure infrastructure, cloud-init configures the virtual machine at first boot, and Docker Compose runs the monitoring stack. Nobody logs into the server to deploy anything: the VM installs Docker, clones this repository and starts the stack by itself.

What it collects and shows:

- **Prometheus** scrapes metrics every 15 seconds and stores them, and evaluates 9 alert rules covering host availability, CPU, memory, disk, container health and the health of the monitoring system itself.
- **Grafana** displays them on a provisioned dashboard, with the datasource and dashboard both defined in files rather than clicked together in the UI.
- **node-exporter** reports the virtual machine: CPU, memory, disk, filesystem and network.
- **cAdvisor** reports the containers running on it.

Metric and dashboard state is written to a separate Azure managed disk mounted at `/data`. Because Terraform treats that disk as its own resource, the virtual machine can be destroyed and rebuilt from scratch and the history survives.

```
project13/
├── infra/      Terraform. Resource group, network, firewall, VM, data disk
├── stack/      Docker Compose stack that runs on the VM
├── scripts/    Bash automation for setup, deployment and health checking
└── README.md
```

---

## 2. Requirements

**Accounts**

| Requirement | Notes |
|---|---|
| Microsoft Azure subscription | A free trial is sufficient. Note the 4 vCPU per region quota |
| GitHub account | The repository must be **public**, because cloud-init clones it with no credentials |

**Tools**

| Tool | Version | Where it runs |
|---|---|---|
| Terraform | >= 1.9.0 | Azure Cloud Shell, or your own machine |
| Azure CLI | any current version | Azure Cloud Shell, or your own machine |
| Git | any current version | Azure Cloud Shell, or your own machine |
| Docker Engine | 24 or newer | Installed automatically on the VM by cloud-init |
| Docker Compose plugin | v2 | Installed automatically on the VM by cloud-init |

Azure Cloud Shell already has Terraform, the Azure CLI and Git, so no local installation is needed. It does **not** have the Docker Compose plugin, but Compose only ever runs on the VM.

**Azure provider**

`hashicorp/azurerm ~> 4.0`, pinned by `infra/.terraform.lock.hcl`. Note that provider v4 requires `subscription_id` to be set explicitly.

**Resource providers** that must be registered on the subscription:

```bash
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage
```

---

## 3. Installation

**1. Clone the repository**

```bash
git clone https://github.com/adeebs396-eng/project13.git
cd project13
```

**2. Sign in to Azure and select the subscription**

```bash
az login
az account set --subscription "<your-subscription-name>"
az account show --query id -o tsv
```

**3. Create an SSH key pair**, if you do not have one. No passphrase, so automation can use it.

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

**4. Create your variables file**

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in the values. See section 5 for what each one means. `terraform.tfvars` is gitignored and must never be committed.

**5. Initialise Terraform**

```bash
terraform init
terraform validate
```

---

## 4. Run the Project

**Create the infrastructure**

```bash
cd infra
terraform plan
terraform apply
```

Expect 13 Azure resources. Review the plan before confirming.

**Wait about four minutes.** The VM is doing this by itself, with nobody logged into it:

1. installs Docker and the Compose plugin
2. formats and mounts the data disk at `/data`, or mounts the existing filesystem if one is already there
3. clones this repository
4. writes `stack/.env` with the Grafana credentials
5. runs `docker compose up -d`

**Get the addresses**

```bash
terraform output
```

| Output | What it is |
|---|---|
| `public_ip` | The VM's static public IP |
| `grafana_url` | Grafana, port 3000 |
| `prometheus_url` | Prometheus, port 9090 |
| `ssh_command` | Ready to paste SSH command |
| `data_disk_name` | The persistent disk holding metric history |

**Check it worked**

```bash
bash scripts/health-check.sh
```

Runs 7 checks covering containers, Prometheus, every scrape target, alert rules, Grafana, the datasource and the provisioned dashboards. Exits non-zero if any fail, so it is safe in cron or CI.

**Other scripts**

```bash
bash scripts/start-services.sh     # bring the stack up
bash scripts/check-logs.sh         # last 100 lines from every service
bash scripts/check-logs.sh --errors   # only warnings and errors
bash infra/allow-my-ip.sh 1.2.3.4  # add an IP to the firewall and apply
```

**Redeploy after a change**

```bash
git pull
cd infra && terraform apply
```

Changes to `stack/` reach the VM on its next `git pull`. Note that `prometheus.yml` is mounted as a single file, so a configuration change needs `docker compose up -d --force-recreate prometheus` rather than a reload. Alert rules are in a directory mount, so those only need `curl -X POST http://localhost:9090/-/reload`.

**Rebuild the VM from nothing**

```bash
cd infra
terraform apply -replace="azurerm_linux_virtual_machine.main" -auto-approve
```

Destroys the machine and its OS disk and rebuilds it from this repository. The public IP, the firewall rules and the data disk with all metric history survive.

**Stop paying without losing anything**

```bash
az vm deallocate -g obs2-rg -n obs2-vm
az vm start -g obs2-rg -n obs2-vm
```

---

## 5. API Keys & Environment Variables

There are no API keys. Authentication to Azure is handled by `az login`, and there are no third party services.

### `infra/terraform.tfvars` (gitignored, never commit)

Copy from `infra/terraform.tfvars.example`.

| Variable | Required | Default | What it is |
|---|---|---|---|
| `subscription_id` | **yes** | none | Azure subscription GUID, from `az account show --query id -o tsv` |
| `allowed_source_ips` | **yes** | none | List of IPs allowed through the firewall on ports 22, 9090 and 3000. Get yours from https://ipv4.icanhazip.com **in a browser**, not Cloud Shell |
| `grafana_admin_password` | **yes** | none | Grafana admin password. Marked `sensitive`, so Terraform will not print it |
| `prefix` | no | `obs2` | Name prefix for every resource |
| `location` | no | `westus3` | Azure region |
| `vm_size` | no | `Standard_D2s_v7` | VM size. West US 3 only offers v7 generation sizes to this subscription |
| `admin_username` | no | `azureuser` | Linux user on the VM |
| `ssh_public_key_path` | no | `~/.ssh/id_rsa.pub` | Public key installed on the VM |
| `extra_ssh_public_keys` | no | `[]` | Additional public keys for teammates |
| `extra_allowed_ips` | no | `[]` | Additional IPs, merged with `allowed_source_ips` |
| `repo_url` | no | `""` | Repository cloned at first boot. Empty means no auto deploy |
| `grafana_admin_user` | no | `admin` | Grafana admin username |
| `data_disk_size_gb` | no | `32` | Size of the persistent data disk |
| `data_disk_lun` | no | `10` | LUN the data disk attaches at |

Those three required variables have no defaults on purpose, so Terraform refuses to run without explicit values rather than silently using something insecure.

### `stack/.env` (gitignored, never commit)

Written automatically by cloud-init on the VM. Create it by hand only when running the stack somewhere else:

```bash
cd stack
cp .env.example .env
```

| Variable | Default | What it is |
|---|---|---|
| `GF_ADMIN_USER` | `admin` | Grafana admin username |
| `GF_ADMIN_PASSWORD` | none | Grafana admin password |
| `GRAFANA_PORT` | `3000` | Published Grafana port |
| `PROMETHEUS_PORT` | `9090` | Published Prometheus port |
| `PROMETHEUS_RETENTION_TIME` | `15d` | How long metrics are kept |
| `DATA_ROOT` | `/data` | Where Prometheus and Grafana write state. On the VM this is the persistent disk |

### Files that must never be committed

`.gitignore` blocks all of these, which is what makes a public repository safe:

```
.terraform/     *.tfstate     *.tfstate.*
*.tfvars        *.tfvars.*    tfplan        plan.txt
.env            *.pem         id_rsa*       .DS_Store
```

Check before every push:

```bash
git status --short
```

---

## 6. Known Issues

**cAdvisor does not report container names.** `container_last_seen{name!=""}` returns nothing on the VM, so cAdvisor produces cgroup IDs instead of container names. The `ContainerDisappeared` alert therefore cannot fire, and the Docker panel on the dashboard shows cgroup paths instead of readable names. A `CadvisorNotReportingContainerNames` alert exists specifically to flag this, so the gap is visible rather than silent. Cause not yet confirmed; changing the `/var/run` mount from read-only to read-write did not fix it.

**Terraform state is local.** `terraform.tfstate` lives in the working directory, so only one person can run `apply`, and losing the file means losing track of the live resources. The fix is an Azure Storage backend with state locking, migrated with `terraform init -migrate-state`.

**No alert routing.** Alerts fire inside Prometheus and are visible at `/alerts`, but there is no Alertmanager, so nothing sends them to email, Slack or anywhere else. Adding Alertmanager is the next step.

**`terraform destroy` will not run.** The data disk has `prevent_destroy = true`, so destroy fails at plan time and destroys nothing. This is deliberate, because that disk holds the only state that cannot be rebuilt. To genuinely delete everything, remove the `lifecycle` block from `azurerm_managed_disk.data` first.

**A rebuild leaves a gap in the graphs.** Metric history survives a VM rebuild because it is on the data disk, but nothing is scraping while the machine does not exist, so there is a hole covering the rebuild window. This is correct behaviour, not a fault.

**Grafana logs a `failed to update managedFields` error on startup.** The dashboard uses Grafana's v2 schema, which file provisioning loads correctly but logs a schema conversion error about. Known cosmetic bug in Grafana 13; the dashboard loads normally.

**Editing `prometheus.yml` needs a container recreate, not a reload.** The file is a single-file bind mount, and Git replaces files rather than editing them in place, so the container keeps reading the old version. `POST /-/reload` reports success while doing nothing. Use `docker compose up -d --force-recreate prometheus`.

**Free trial constraints.** The subscription is limited to 4 vCPU per region, and West US 3 only offers v7 generation VM sizes to it. Other sizes fail with `SkuNotAvailable` at create time, which `az vm list-skus` does not predict, because its `restrictions` field reports policy blocks rather than live capacity.
