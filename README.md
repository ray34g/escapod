# Escapod

Small, self‑contained helper that **collects system information, backs it up to S3,  
e‑mails the snapshot via Amazon SES, and integrates cleanly into system shutdown/reboot**  
with support for **Fedora CoreOS** or any systemd-based host.

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
escapod/
├── escapod.sh
├── systemd/
│   └── escapod.service
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
git clone https://github.com/ray34g/escapod.git
cd escapod

sudo mkdir -p /etc/escapod
sudo cp escapod.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/escapod.sh

sudo cp systemd/escapod.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable escapod.service
```

> **Ignition/Butane** users: embed the same files under `/usr/local/bin/…` and enable the units in your Butane spec.

------

## Configuration

Edit the variables at the top of `/opt/escapod/escapod.sh`.

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
sudo /usr/local/bin/escapod/escapod.sh
# check mail & s3://$S3_BUCKET/$S3_PREFIX/
```

------

## Uninstall

```
sudo systemctl disable escapod.service
sudo rm -f /etc/systemd/system/escapod.service
sudo rm -rf /etc/escapod /var/log/escapod
```

------

## Extending

- Add more `log …` lines to collect extra data.
- Use S3 lifecycle rules for retention.
- Swap SES for any mailer—just edit `send_mail()`.

Enjoy safe, observable reboots!