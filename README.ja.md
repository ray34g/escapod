# pre‑reboot‑hook

システムのシャットダウンや再起動前に、**情報収集・S3バックアップ・SESメール送信**を行う小さなフックスクリプトです。

**Fedora CoreOS**（/usr が読み取り専用）向けに調整していますが、  
Podman が入った任意の systemd Linux で動作します。

---

## 特長
- 各種システム情報を収集：uptime、ログインユーザー、ネットワーク、`sysctl -a`、sysstat、Kubernetes / CRI-O / Compose 情報など
- S3 へのバックアップと SES 経由のメール送信を並列実行
- シャットダウン時に systemd サービスとして動作し、完了まで処理をブロック
- `KEEP_LOCAL_BACKUP=true` のとき、ローカルに最新の `.tgz` を 1 つ保持
- 実行に必要なのは **AWS CLI** のみ

---

## 構成
```bash
escapod/
├── escapod.sh          # メインスクリプト
└── systemd/
    └── escapod.service # 再起動シーケンスで実行
```


## 前提

| 項目                              | 備考                                                      |
| --------------------------------- | --------------------------------------------------------- |
| Fedora CoreOS 39+ または任意のsystemd対応ディストリ | systemd ベースの Linux であれば OK                        |
| AWS CLI v2                        | S3 および SES の送信に必要                                |
| `/root/.aws/{config,credentials}` | `aws configure` で事前に作成                             |
| オプションツール                  | `sysstat`, `kubelet`, `crio` などが導入されていれば収集が拡張される |

---

## インストール手順

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

> **Ignition / Butane** を使う場合：スクリプトを `/usr/local/bin/` に配置し、Butane YAML でユニットを有効化してください。

------

設定方法

`/usr/local/bin/escapod.sh` の冒頭にある変数を編集します。

| 変数名                  | 内容                      | 例                                      |
| ----------------------- | ------------------------- | ---------------------------------------- |
| `BACKUP_PATHS`          | アーカイブ対象ディレクトリ | `(/etc /var/lib/kubelet)`                |
| `S3_BUCKET` / `S3_PREFIX` | S3アップロード先            | `my-bkt` / `pre_reboot/$(hostname)`      |
| `KEEP_LOCAL_BACKUP`     | ローカルに保存するか       | `true` / `false`                         |
| `TO_ADDRS` / `FROM_ADDR`| SES宛先と送信元アドレス     | `ops@example.test`                       |
| `AWS_REGION`            | AWSリージョン              | `ap-northeast-1`                         |


------

## テスト実行

```bash
sudo /usr/local/bin/escapod.sh
# メールの受信と S3 バケットを確認
```

------

## アンインストール

```bash
sudo systemctl disable escapod.service
sudo rm -f /etc/systemd/system/escapod.service
sudo rm -rf /etc/escapod /var/log/escapod
```

---

## 拡張方法

- ログ収集を追加したい場合は `log …` 行を追記
- S3 ライフサイクルルールで保持期限の制御も可能
- `send_mail()` 関数を編集して、他の送信方法に差し替えも可能

安全・快適な再起動運用にお役立てください！