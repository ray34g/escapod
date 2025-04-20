# pre‑reboot‑hook

Small, self‑contained helper that **collects system information, backs it up to S3,  
e‑mails the snapshot via Amazon SES, and integrates cleanly into system shutdown/reboot**  
with full support for **Fedora CoreOS** or any systemd-based host.

---

## Features

* Rich snapshot: uptime, users, network, `sysctl -a`, sysstat, Kubernetes/CRI-O/Compose info, …
* S3 backup **and** SES email notification
* Runs during **shutdown phase**, blocking reboot until backup is complete
* Keeps **one** local log/backup if `KEEP_LOCAL_BACKUP=true`
* Only runtime dependencies: **AWS CLI**, **mailx or SES-compatible toolset**

---

## Directory layout

```bash
pre-reboot-hook/
├── pre-reboot-hook.sh
├── systemd/
│   └── pre-reboot-hook.service
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
| Optional tools (already present in sample node) | `cri-o  docker-compose  kubeadm  kubectl  kubelet  sysstat` |

---

## Installation

```bash
git clone https://github.com/ray34g/pre-reboot-hook.git
cd pre-reboot-hook

sudo mkdir -p /etc/pre-reboot-hook
sudo cp pre-reboot-hook.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/pre-reboot-hook.sh

sudo cp systemd/pre-reboot-hook.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pre-reboot-hook.service
```

> **Ignition/Butane** users: embed the same files under `/usr/local/bin/…` and enable the units in your Butane spec.

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

------

## Manual test

```
sudo /usr/local/bin/pre-reboot-hook/pre-reboot-hook.sh
# check mail & s3://$S3_BUCKET/$S3_PREFIX/
```

------

## Uninstall

```
sudo systemctl disable pre-reboot-hook.service
sudo rm -f /etc/systemd/system/pre-reboot-hook.service
sudo rm -rf /etc/pre-reboot-hook /var/log/pre-reboot-hook
```

------

## Extending

- Add more `log …` lines to collect extra data.
- Use S3 lifecycle rules for retention.
- Swap SES for any mailer—just edit `send_mail()`.

Enjoy safe, observable reboots!