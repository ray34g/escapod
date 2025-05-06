## 日本語版 README（最新版）

# Escapod

**システム診断情報を収集し、S3にバックアップし、Amazon SESを通じてスナップショットをメールで送信。  
予定されたシャットダウン／再起動イベントとシームレスに連携する**  
**Fedora CoreOS** およびその他の systemd ベースのシステム用の小型・自立型ツールです。

---

## 特徴

* 詳細なスナップショット: uptime、ユーザー、ネットワーク、sysctl、sysstat、Kubernetes / CRI-O / Compose 情報など
* S3 バックアップ **および** SES メール通知（オプション。各フェーズごとに有効/無効を切替可能）
* **3つのフェーズ**で実行：
  * `scheduled` – 再起動が予定されたとき
  * `pre-reboot` – シャットダウン／再起動が始まる直前
  * `post-reboot` – 再起動が完了した後（実際に再起動が実行された場合のみ）
* **ローテーションされたログ** と **オプションのローカルバックアップ** を保持
* 柔軟な環境変数ベースの構成（`escapod.env`）
* systemd で呼び出された場合、**systemd-notify** による通知に対応
* 実行時依存性は **AWS CLI** のみ

---

## ディレクトリ構造

```shell
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

## 前提条件

| コンポーネント                            | 備考                                                |
| ----------------------------------------- | --------------------------------------------------- |
| Fedora CoreOS 39以上                      | または任意の systemd ベースのディストリビューション |
| AWS **SES** & **S3**                      | SMTP 資格情報とターゲットバケット                   |
| `/root/.aws/{config,credentials}`         | `aws configure` で作成                              |
| オプション：`cri-o`, `docker-compose`など | インストールされていれば自動検出                    |



------

## インストール

```shell
git clone https://github.com/ray34g/escapod.git
cd escapod

sudo ./install.sh
```

この操作により：

- `escapod.sh` を `/usr/local/bin/` に配置
- `escapod.env` を `/etc/escapod/` にコピー
- すべての systemd ユニットをインストール＆有効化：
  - `escapod.service`
  - `escapod-scheduled.service`
  - `escapod-scheduled.path`
  - `escapod-post.service`

> **注意**: `install.sh` スクリプトは既存の `escapod.env` ファイルを保持します。

------

## フェーズ（動作タイミング）

| フェーズ      | トリガー                                 | 説明                                         |
| ------------- | ---------------------------------------- | -------------------------------------------- |
| `scheduled`   | 新しいシャットダウン／再起動予定イベント | 再起動がスケジュールされたことを記録し通知   |
| `pre-reboot`  | 実際のシャットダウン／再起動中           | 再起動前にデータをバックアップし通知         |
| `post-reboot` | 再起動成功後                             | 実際に再起動された場合のみ、ログと通知を実行 |



**再起動の検出方法:**
 `pre-reboot` フェーズでフラグを設定します。
 システムがこのフラグなしで起動した場合（コールドブートなど）、`post-reboot` のアクションは実行されません。

------

## 設定

動作を調整するには、`/etc/escapod/escapod.env` を編集します。

| 変数                      | 説明                            | 例                                     |
| ------------------------- | ------------------------------- | -------------------------------------- |
| `BACKUP_PATHS`            | バックアップするディレクトリ    | `(/etc /var/lib/kubelet)`              |
| `S3_BUCKET` / `S3_PREFIX` | S3 の保存先                     | `my-bkt` / `pre_reboot/$(hostname)`    |
| `KEEP_LOCAL_BACKUP`       | ローカル TGZ アーカイブを保存   | `true` / `false`                       |
| `MAIL_ENABLED`            | SES メールを送信する            | `true` / `false`                       |
| `BACKUP_ENABLED`          | バックアップ処理を有効にする    | `true` / `false`                       |
| `TO_ADDRS` / `FROM_ADDR`  | SES のメールアドレス            | `ops@example.test`                     |
| `AWS_REGION`              | SES/S3 用のリージョン           | `ap-northeast-1`                       |
| `AWS_CLI_PATH`            | AWS CLI のバイナリまたは Podman | `/usr/bin/aws` または `podman run ...` |



------

## 手動テスト

任意のフェーズを手動でテストできます：

```shell
sudo /usr/local/bin/escapod.sh scheduled
sudo /usr/local/bin/escapod.sh pre-reboot
sudo /usr/local/bin/escapod.sh post-reboot
```

ログの確認：

```shell
cat /var/log/escapod/info_*.log
```

メール配信と S3 バックアップ（有効化されていれば）も確認してください。

------

## アンインストール

```shell
sudo systemctl disable escapod.service escapod-scheduled.service escapod-post.service
sudo systemctl disable --now escapod-scheduled.path
sudo rm -f /etc/systemd/system/escapod*.service /etc/systemd/system/escapod-scheduled.path
sudo rm -f /usr/local/bin/escapod.sh
sudo rm -rf /etc/escapod /var/log/escapod
```shell

------

## 拡張

- `escapod.sh` にさらに `log ...` 行を追加して追加診断情報を収集可能。
- `send_mail()` 関数をカスタマイズし、他のメールツールにも対応可能。
- S3 ライフサイクルルールを利用して古いバックアップを期限切れに設定可能。
- 高度な AWS CLI 設定のために Podman を統合可能。

安全で観測可能な再起動をお楽しみください！