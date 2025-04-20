# pre‑reboot‑hook

**システム情報を収集 → S3 にバックアップ → Amazon SES でメール送信 →  
1 分後に安全に再起動** する最小構成スクリプトです。

**Fedora CoreOS**（/usr が読み取り専用）向けに調整していますが、  
Podman が入った任意の systemd Linux で動作します。

---

## 特長
* 豊富なスナップショット（uptime・ユーザ・ネットワーク・`sysctl -a`・sysstat など）  
  必要に応じて `pre-reboot-hook.sh` に追記可能
* **S3 バックアップと SES メール送信を並列実行** → 待ち時間最小
* `systemd.timer` で **1 分の猶予**（変更可）
* ローカルのログ／バックアップは **最新 1 世代のみ**（変数で ON/OFF）
* 追加依存は **Podman** だけ（`amazon/aws-cli` イメージを実行）

---

## 構成
```bash
pre-reboot-hook/
├── pre-reboot-hook.sh          # メインスクリプト
├── systemd/
│   ├── pre-reboot-hook.service # 再起動シーケンスで実行
│   ├── delayed-reboot.service  # 実際に reboot を呼ぶ
│   └── delayed-reboot.timer    # 1 分後に delayed‑reboot.service 起動
└── LICENSE
```


## 前提

| 項目 | 説明 |
|------|------|
| Fedora CoreOS 39+ | または Podman 4+ 搭載の systemd Linux |
| Podman | FCOS に標準装備 |
| AWS アカウント | **SES** (SMTP 資格情報) と **S3** バケット |
| `/root/.aws/{config,credentials}` | `aws configure` で作成 |
| 追加ツール（例） | `cri-o  docker-compose  kubeadm  kubectl  kubelet  nfs-utils  sysstat` |

---

## インストール手順

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

# 初回のみ aws-cli イメージを取得
sudo podman pull amazon/aws-cli
```

> **Ignition / Butane**
>  初期プロビジョニング時に `/opt/…` へ配置し、ユニットを `enabled: true` にすると 自動適用できます。

------

## 変数設定

`/opt/pre-reboot-hook/pre-reboot-hook.sh` の冒頭を編集してください。



| 変数                      | 意味                         | 例                                  |
| ------------------------- | ---------------------------- | ----------------------------------- |
| `BACKUP_PATHS`            | バックアップ対象ディレクトリ | `(/etc /var/lib/kubelet)`           |
| `S3_BUCKET` / `S3_PREFIX` | S3 バケット／プレフィックス  | `my-bkt` / `pre_reboot/$(hostname)` |
| `KEEP_LOCAL_BACKUP`       | ローカルに TGZ を残すか      | `true` / `false`                    |
| `TO_ADDRS` / `FROM_ADDR`  | SES 送信／受信アドレス       | `ops@example.test`                  |
| `AWS_REGION`              | SES・S3 のリージョン         | `ap-northeast-1`                    |

1 分の猶予を変えたい場合は `delayed-reboot.timer` の `OnActiveSec=1min` を編集してください。

------

## テスト実行

```bash
sudo /opt/pre-reboot-hook/pre-reboot-hook.sh
# メール受信と s3://$S3_BUCKET/$S3_PREFIX/<STAMP>/ の TGZ を確認
```

------

## アンインストール

```bash
sudo systemctl disable delayed-reboot.timer pre-reboot-hook.service
sudo rm -f /etc/systemd/system/delayed-reboot.* /etc/systemd/system/pre-reboot-hook.*
sudo rm -rf /opt/pre-reboot-hook /var/log/pre_reboot
```

------

## 拡張のヒント

- `log …` 行を追加して収集項目を増やす
- S3 ライフサイクルルールで自動削除ポリシーを設定
- メール送信を別ツールに差し替える場合は `send_mail()` を編集

安全・快適な再起動運用にお役立てください！