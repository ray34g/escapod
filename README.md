# pre‑reboot‑hook

Small, self‑contained helper that **collects system information, backs it up to S3,
e‑mails the snapshot via Amazon SES, and reboots the host after a 1‑minute grace period.**

Designed for **Fedora CoreOS** (immutable `/usr`) but works on any modern systemd host
with **Podman** installed.

---

## Features

* Rich snapshot: uptime, users, network, `sysctl ‑a`, sysstat, k8s/CRI‑O/Compose info, …  
  (add more in `pre‑reboot‑hook.sh`)
* Parallel S3 backup **and** SES mail (minimal delay)
* 60‑second grace via `systemd.timer`
* Keeps **one** local log/backup if `KEEP_LOCAL_BACKUP=true`
* Only runtime dependency: **Podman** (`amazon/aws‑cli` image)

---

## Directory layout

```bash
pre-reboot-hook/
├── pre-reboot-hook.sh
├── systemd/
│   ├── pre-reboot-hook.service
│   ├── delayed-reboot.service
│   └── delayed-reboot.timer
└── LICENSE
```

---

## Prerequisites

| Item                                            | Notes                                                        |
| ----------------------------------------------- | ------------------------------------------------------------ |
| Fedora CoreOS 39+                               | or any systemd distro with Podman 4+                         |
| Podman                                          | pre‑installed on FCOS                                        |
| AWS **SES** & **S3**                            | SMTP credentials + target bucket                             |
| `/root/.aws/{config,credentials}`               | created by `aws configure`                                   |
| Optional tools (already present in sample node) | `cri-o  docker-compose  kubeadm  kubectl  kubelet  nfs-utils  sysstat` |

---

## Installation

```bash
git clone https://github.com/ray34g/pre-reboot-hook.git
cd pre-reboot-hook

sudo mkdir -p /opt/pre-reboot-hook
sudo cp pre-reboot-hook.sh /opt/pre-reboot-hook/
sudo chmod 755 /opt/pre-reboot-hook/pre-reboot-hook.sh

sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pre-reboot-hook.service
sudo systemctl enable delayed-reboot.timer

# first run pulls the image
sudo podman pull amazon/aws-cli
```

> **Ignition/Butane** users: embed the same files under `/opt/…` and enable the units in your Butane spec.

------

## Configuration

Edit the variables at the top of `/opt/pre-reboot-hook/pre-reboot-hook.sh`.

| Variable                  | Description        | Example                             |
| ------------------------- | ------------------ | ----------------------------------- |
| `BACKUP_PATHS`            | dirs to archive    | `(/etc /var/lib/kubelet)`           |
| `S3_BUCKET` / `S3_PREFIX` | S3 target          | `my-bkt` / `pre_reboot/$(hostname)` |
| `KEEP_LOCAL_BACKUP`       | keep local TGZ     | `true` / `false`                    |
| `TO_ADDRS` / `FROM_ADDR`  | SES mail addresses | `ops@example.test`                  |
| `AWS_REGION`              | region for SES/S3  | `ap-northeast-1`                    |

Change `OnActiveSec=1min` in `delayed-reboot.timer` for a different grace length.

------

## Manual test

```
sudo /opt/pre-reboot-hook/pre-reboot-hook.sh
# check mail & s3://$S3_BUCKET/$S3_PREFIX/<STAMP>/
```

------

## Uninstall

```
sudo systemctl disable delayed-reboot.timer pre-reboot-hook.service
sudo rm -f /etc/systemd/system/delayed-reboot.* /etc/systemd/system/pre-reboot-hook.*
sudo rm -rf /opt/pre-reboot-hook /var/log/pre_reboot
```

------

## Extending

- Add more `log …` lines to collect extra data.
- Use S3 lifecycle rules for retention.
- Swap SES for any mailer—just edit `send_mail()`.

Enjoy safe, observable reboots!