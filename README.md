# Escapod

A small, self-contained tool that **collects system diagnostics, backs them up to S3,  
e-mails the snapshot via Amazon SES, and integrates seamlessly with scheduled shutdown/reboot events**  
on **Fedora CoreOS** and other systemd-based systems.

---

## Features

* Rich snapshot: uptime, users, network, sysctl, sysstat, Kubernetes/CRI-O/Compose info, etc.
* S3 backup **and** SES email notification (optional, both can be toggled per phase)
* Runs during **three phases**:
  * `scheduled` – when a reboot is planned
  * `pre-reboot` – just before shutdown/reboot starts
  * `post-reboot` – after a reboot completes (only if a reboot was performed)
* Keeps **rotated logs** and **optional local backups**
* Flexible environment-based configuration (`escapod.env`)
* Supports **systemd-notify** for system-aware notifications (if invoked via systemd)
* Minimal runtime dependencies: **AWS CLI** only

---

## Directory structure

```bash
escapod/
├── escapod.sh
├── escapod.env
├── systemd/
│   ├── escapod.service
│   ├── escapod-scheduled.service
│   ├── escapod-scheduled.path
│   └── escapod-post.service
├── install.sh
├── README.md
├── README.ja.md
└── .gitignore
```

------

## Prerequisites

| Component                                 | Notes                               |
| ----------------------------------------- | ----------------------------------- |
| Fedora CoreOS 39+                         | or any systemd distro               |
| AWS **SES** & **S3**                      | SMTP credentials + target bucket    |
| `/root/.aws/{config,credentials}`         | created by `aws configure`          |
| Optional: `cri-o`, `docker-compose`, etc. | Detected automatically if installed |



------

## Installation

```bash
git clone https://github.com/ray34g/escapod.git
cd escapod

sudo ./install.sh
```

This will:

- Deploy `escapod.sh` to `/usr/local/bin/`
- Copy `escapod.env` to `/etc/escapod/`
- Install and enable all systemd units:
  - `escapod.service`
  - `escapod-scheduled.service`
  - `escapod-scheduled.path`
  - `escapod-post.service`

> **Note**: The `install.sh` script preserves existing `escapod.env` files.

------

## Phases

| Phase         | Trigger                             | Description                                               |
| ------------- | ----------------------------------- | --------------------------------------------------------- |
| `scheduled`   | New scheduled shutdown/reboot event | Logs and notifies when a reboot has been scheduled        |
| `pre-reboot`  | During actual shutdown/reboot       | Backs up data and notifies just before reboot             |
| `post-reboot` | After successful reboot             | Logs and notifies only if a reboot was actually performed |



**Reboot detection:**
 Escapod sets a flag during `pre-reboot`. If the system boots without this flag, no `post-reboot` actions are taken (cold boots are ignored).

------

## Configuration

Edit `/etc/escapod/escapod.env` to adjust behavior.

| Variable                  | Description                  | Example                                    |
| ------------------------- | ---------------------------- | ------------------------------------------ |
| `BACKUP_PATHS`            | Directories to back up       | `(/etc /var/lib/kubelet)`                  |
| `S3_BUCKET` / `S3_PREFIX` | S3 destination               | `my-bkt` / `pre_reboot/$(hostname)`        |
| `KEEP_LOCAL_BACKUP`       | Save local TGZ archives      | `true` / `false`                           |
| `MAIL_ENABLED`            | Send SES emails              | `true` / `false`                           |
| `BACKUP_ENABLED`          | Enable backup process        | `true` / `false`                           |
| `TO_ADDRS` / `FROM_ADDR`  | SES email addresses          | `ops@example.test`                         |
| `AWS_REGION`              | AWS region                   | `ap-northeast-1`                           |
| `AWS_CLI_PATH`            | AWS CLI binary or Podman cmd | `/usr/bin/aws` or `podman run ... aws-cli` |



------

## Manual test

You can test a single phase manually:

```bash
sudo /usr/local/bin/escapod.sh scheduled
sudo /usr/local/bin/escapod.sh pre-reboot
sudo /usr/local/bin/escapod.sh post-reboot
```

Check the logs:

```bash
cat /var/log/escapod/info_*.log
```

And verify mail delivery + S3 backups if enabled.

------

## Uninstall

```bash
sudo systemctl disable escapod.service escapod-scheduled.service escapod-post.service
sudo systemctl disable --now escapod-scheduled.path
sudo rm -f /etc/systemd/system/escapod*.service /etc/systemd/system/escapod-scheduled.path
sudo rm -f /usr/local/bin/escapod.sh
sudo rm -rf /etc/escapod /var/log/escapod
```

------

## Extending

- Add more `log …` lines in `escapod.sh` to collect extra diagnostics.
- Customize the `send_mail()` function for alternative email tools.
- Use S3 lifecycle rules to expire older backups.
- Integrate Podman for more advanced AWS CLI setups.

Enjoy safe, observable reboots!
