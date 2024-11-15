# 概要

大まかな手順は以下。

1. yumリポジトリのミラーを作成
2. コンテナレジストリのミラーを作成
3. オペレーターノード、コントロールプレーン、ワーカーノードの諸準備
4. OCNEのインストール
5. OCNE環境の作成
6. Kubernetesモジュールのインストール

# インフラの構成

- 踏み台兼ミラーサーバのノード（パブリックサブネットに配置）
- オペレーターノード（プライベートサブネットに配置）
- コントロールプレーン（プライベートサブネットに配置）
- ワーカーノード（プライベートサブネットに配置）
- ロードバランサ（プライベートサブネットに配置、コントロールプレーンをバックエンドセットにする）
- DNS（プライベートゾーンを各ノードとLBに設定）

# yumリポジトリのミラーを作成

この作業はミラーサーバー（踏み台サーバ）で行う。

## 作業概要

- リリースパッケージをミラーサーバーに入れる
- ミラーするyumレポジトリの内容をダウンロード
- httpdでホスティング

## リリースパッケージをミラーサーバーに入れる

```bash
sudo dnf install oracle-olcne-release-el8 # Oracle linux9の場合はel9
```

使用しているカーネルを確認。

```bash
[opc@mirror ~]$ uname -r
5.15.0-210.163.7.el8uek.x86_64
```

Oracleのカーネルバージョンは、

- UEK R6: 5.4系
- UEK R7: 5.15系
らしいので、今回はUEK R7になる。

下記のコマンドでレポジトリを有効化する（このコマンドはカーネルによって異なる）。

```bash
sudo dnf config-manager --enable ol8_olcne17 ol8_addons ol8_baseos_latest ol8_appstream ol8_kvm_appstream ol8_UEKR7
```

## ミラーするyumレポジトリの内容をダウンロード

下記のコマンドで必要なレポジトリの内容をダウンロード。

```bash
sudo dnf reposync --enablerepo=ol8_olcne17 --enablerepo=ol8_baseos_latest --enablerepo=ol8_appstream --destdir=/mnt/local-yum-repo --download-metadata --newest-only
```

全てのレポジトリからダウンロードしたパッケージを一つのディレクトリに統合する。

```bash
sudo cp -r /mnt/local-yum-repo/ol8_addons/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_appstream/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_baseos_latest/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_ksplice/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_kvm_appstream/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_MySQL80/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_MySQL80_connectors_community/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_MySQL80_tools_community/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_oci_included/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_olcne17/* /mnt/local-yum-repo/combined_repo/
sudo cp -r /mnt/local-yum-repo/ol8_UEKR7/* /mnt/local-yum-repo/combined_repo/
```

統合ディレクトリでメタデータを生成。

```bash
sudo createrepo /mnt/local-yum-repo/combined_repo
```

## httpdでホスティング

まず、Apacheを入れる。

```bash
sudo dnf install httpd -y
```

次に、レポジトリの統合ディレクトリをApacheの公開ディレクトリとして設定する。`/etc/httpd/conf.d/local-repo.conf`を作成し、以下の内容を書く。

```
<VirtualHost *:80>
    ServerName mirror.migration.ora
    DocumentRoot /mnt/local-yum-repo/combined_repo
    <Directory /mnt/local-yum-repo/combined_repo>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
```

`ServerName`にはIPアドレス化ホスト名を書く。ここではミラーサーバーのホスト名（プライベートゾーンに登録済み）を書いた。

最後に、Apacheの起動とポート80の許可を行う。

```bash
sudo systemctl start httpd
sudo systemctl enable httpd
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

# コンテナレジストリのミラーを作成

この作業は踏み台兼ミラーサーバーで行う。

## 作業概要

- コンテナレジストリをホストするコンテナを作成
- ローカルのコンテナレジストリを利用する設定
- 必要なイメージをローカルのコンテナレジストリにプッシュ

## コンテナレジストリをホストするコンテナを作成

まず、Podmanを入れる。

```bash
sudo dnf module install container-tools:ol8
```

プライベートレジストリを作成するためのコンテナイメージをダウンロードするため、レジストリにログインする。

```bash
sudo podman login container-registry.oracle.com
```

ユーザー名はメールアドレス、パスワードは認証トークンを
<https://container-registry.oracle.com/ords/f?p=113:10>::::::
からとる。
下記のコマンドでレジストリを起動する。

```bash
sudo podman run -d -p 5000:5000 --name registry --restart=always -v /mnt/ocr-mirror:/registry_data -e REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/registry_data -e REGISTRY_AUTH="" container-registry.oracle.com/os/registry:v2.7.1.1
```

`-v`オプションで、コンテナイメージを保存する場所をマウントする。ここでは、`/mnt/ocr-mirror`をマウントしている。

## ローカルのコンテナレジストリを利用する設定

`/etc/containers/registries.conf`を以下のように編集する。

```
# unqualified-search-registries = ["container-registry.oracle.com", "docker.io"]

# 設定例: HTTPを許可するコンテナレジストリ（ポート5000）
[[registry]]
prefix = "mirror.migration.ora:5000/olcne"
location = "mirror.migration.ora:5000/olcne"
insecure = true

short-name-mode = "permissive"
```

## 必要なイメージをローカルのコンテナレジストリにプッシュ

まずは、必要なイメージをプッシュするためのヘルパーを利用するため、`olcne-utils`を入れる。

```bash
sudo dnf install olcne-utils
```

本来は`registry-image-helper.sh`でイメージのプルとプッシュを行うが、下記のイメージが利用不可。

```
container-registry.oracle.com/olcne/rook:v1.10.9-1
container-registry.oracle.com/olcne/rook:v1.11.6-2
quay.io/k8scsi/csi-node-driver-registrar:v1.0.2
```

このシェルスクリプトはエラーが出たときに終了してしまうので、当レポジトリの`fixed-registry-image-helper.sh`を利用する。

下記のコマンドでイメージのプルとプッシュを行う。

```bash
./fixed-registry-image-helper.sh --to mirror.migration.ora:5000/olcne
```

# オペレーターノード、コントロールプレーン、ワーカーノードの諸準備

## オペレーターノード

下記のコマンドを実行。

```bash
sudo swapoff -a
sudo cat /etc/fstab
sudo cp /etc/fstab /etc/fstab_copy
sudo sed -i '/\bswap\b/s/^/#/' /etc/fstab
sudo cat /etc/fstab
sudo firewall-cmd --add-port=8091/tcp --permanent
sudo systemctl restart firewalld.service
sudo modprobe br_netfilter
sudo sh -c 'echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf'

#確認
sudo lsmod|grep br_netfilter
```

## コントロールプレーン

```bash
sudo swapoff -a
sudo cat /etc/fstab
sudo cp /etc/fstab /etc/fstab_copy
sudo sed -i '/\bswap\b/s/^/#/' /etc/fstab
sudo cat /etc/fstab
sudo firewall-cmd --zone=trusted --add-interface=cni0 --permanent
sudo firewall-cmd --add-port=8090/tcp --permanent
sudo firewall-cmd --add-port=10250/tcp --permanent
sudo firewall-cmd --add-port=10255/tcp --permanent
sudo firewall-cmd --add-port=8472/udp --permanent
sudo firewall-cmd --add-port=6443/tcp --permanent
sudo firewall-cmd --add-port=10251/tcp --permanent
sudo firewall-cmd --add-port=10252/tcp --permanent
sudo firewall-cmd --add-port=2379/tcp --permanent
sudo firewall-cmd --add-port=2380/tcp --permanent
sudo systemctl restart firewalld.service
sudo modprobe br_netfilter
sudo sh -c 'echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf'

#確認
sudo lsmod|grep br_netfilter
```

## ワーカー

```bash
sudo swapoff -a
sudo cat /etc/fstab
sudo cp /etc/fstab /etc/fstab_copy
sudo sed -i '/\bswap\b/s/^/#/' /etc/fstab
sudo cat /etc/fstab
sudo firewall-cmd --zone=trusted --add-interface=cni0 --permanent
sudo firewall-cmd --add-port=8090/tcp --permanent
sudo firewall-cmd --add-port=10250/tcp --permanent
sudo firewall-cmd --add-port=10255/tcp --permanent
sudo firewall-cmd --add-port=8472/udp --permanent
sudo systemctl restart firewalld.service
sudo modprobe br_netfilter
sudo sh -c 'echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf'

#確認
sudo lsmod|grep br_netfilter
```

# OCNEのインストール

作業は各ノードにわたるので都度指示する。

## 作業概要

- ローカルyumレポジトリの利用設定
- OCNE関連のパッケージインストールと有効化
- 証明書の作成とコピー
- Platform API Serverを起動
- agentを起動

## ローカルyumレポジトリの利用設定

この作業はすべてのノード（オペレータ、コントロールプレーン、ワーカー）で行う。

ローカルレポジトリを利用するため、他のレポジトリを無効化後、ローカルレポジトリの設定ファイルを作成する。
まずは下記のコマンドですべてのレポジトリを無効化。

```bash
sudo sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/*
```

`/etc/yum.repos.d/local-olcne.repo`を作成。

```bash
cat << EOF | sudo tee /etc/yum.repos.d/local-olcne.repo
[local-olcne]
name=Local OLCNE Repo
baseurl=http://mirror.migration.ora/
enabled=1
gpgcheck=0
EOF
```

## OCNE関連のパッケージインストールと有効化

### オペレーター

必要なパッケージをインストール

```bash
sudo dnf install olcnectl olcne-api-server olcne-utils -y
```

`olcne-api-server.service`を有効にする（起動はしない）。

```bash
sudo systemctl enable olcne-api-server.service 
```

### コントロールプレーン、ワーカー

必要なパッケージをインストール

```bash
sudo dnf install olcne-agent olcne-utils -y
```

`olcne-agent`を有効化

```bash
sudo systemctl enable olcne-agent.service 
```

## 証明書の作成とコピー

オペレーターノードで作業を行う。

### ノード間通信のための自己署名証明書作成・コピー

まずディレクトリを移動する。

```bash
cd /etc/olcne
```

次に、下記のコマンドでノード間通信のための自己署名証明書を作成する。

```bash
sudo ./gen-certs-helper.sh \
--cert-request-organization-unit "My Company Unit" \
--cert-request-organization "My Company" \
--cert-request-locality "My Town" \
--cert-request-state "My State" \
--cert-request-country US \
--cert-request-common-name cloud.migration.ora \
--nodes operator.migration.ora,control-plane-1.migration.ora,control-plane-2.migration.ora,control-plane-3.migration.ora,worker-1.migration.ora,worker-2.migration.ora
```

ここで、`--nodes`には実際のコントロールプレーンとワーカーのFQDNを入力する。

作成した証明書を各ノードに転送するために、`/etc/olcne/configs/certificates/olcne-tranfer-certs.sh`を利用する。このシェルスクリプトは各ノードにSSH接続して証明書をコピーするので、オペレーターノードから各ノードにアクセスするための秘密鍵を用意しておく必要がある。今回は`ocne.key`をミラーサーバーから送っておく。

```bash
scp ~/.ssh/ocne.key operator:~/.ssh
```

`/etc/olcne/configs/certificates/olcne-tranfer-certs.sh`のID_FILEを`~/.ssh/ocne.key`に書き換える。書き換えると下記のようになる。

```bash
#!/bin/bash -e
#
# Copyright (c) 2019-2021 Oracle and/or its affiliates. All rights reserved.
# Licensed under the GNU General Public License Version 3 as shown at https://www.gnu.org/licenses/gpl-3.0.txt.

# Temporary script to transfer olcne generated certs to nodes

ID_FILE=~/.ssh/ocne.key
USER=opc

for olcne_node in operator.migration.ora control-plane-1.migration.ora control-plane-2.migration.ora control-plane-3.migration.ora worker-1.migration.ora worker-2.migration.ora; do
    ca_cert_path="/etc/olcne/configs/certificates/production/ca.cert"
    node_key_path_str="/etc/olcne/configs/certificates/tmp-olcne/${olcne_node}/node.key"
    node_cert_path_str="/etc/olcne/configs/certificates/tmp-olcne/${olcne_node}/node.cert"
    SSH="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${ID_FILE} ${USER}@${olcne_node}"
    SCP="scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${ID_FILE}"

    echo "[INFO] Copying certificate files to: '${olcne_node}' as: '${USER}'"

    # Ensure cert directory exists on the remote
    ${SSH} "sudo mkdir -p /etc/olcne/configs/certificates/production"

    # Copy the CA Cert to the remote
    ${SCP} ${ca_cert_path} ${USER}@${olcne_node}:
    ${SSH} "sudo mv ca.cert /etc/olcne/configs/certificates/production/ca.cert"

    # Copy the Node Key to the remote
    ${SCP} ${node_key_path_str} ${USER}@${olcne_node}:
    ${SSH} "sudo mv node.key /etc/olcne/configs/certificates/production/node.key"

    # Copy the Node Cert to the remote
    ${SCP} ${node_cert_path_str} ${USER}@${olcne_node}:
    ${SSH} "sudo mv node.cert /etc/olcne/configs/certificates/production/node.cert"

    # Give the 'olcne' user access to the certs dir
    ${SSH} "sudo chown -R olcne:olcne /etc/olcne/configs/certificates/production"
done

# Validate the 'olcne' user has access all the way to the certificates
sudo -u olcne ls /etc/olcne/configs/certificates/production
```

スクリプト内で権限が無いと動かないので、オペレーターノードで下記を実行しておく。

```bash
sudo chmod -R 755 /etc/olcne/configs/certificates/tmp-olcne
```

スクリプトを実行して証明書をコピーする。

```bash
bash -ex /etc/olcne/configs/certificates/olcne-tranfer-certs.sh
```

各ノードで、下のコマンドを実行して正しく結果が返るかを確認する。

```bash
sudo -u olcne ls /etc/olcne/configs/certificates/production/
```

結果が、

```
ca.cert  node.cert  node.key
```

となればOK。

### externalIPs Kubernetesサービス用に証明書を設定

下記のコマンドをオペレーターノードの`/etc/olcne`で実行。

```bash
sudo ./gen-certs-helper.sh \
--cert-dir /etc/olcne/certificates/restrict_external_ip/ \
--cert-request-organization-unit "My Company Unit" \
--cert-request-organization "My Company" \
--cert-request-locality "My Town" \
--cert-request-state "My State" \
--cert-request-country US \
--cert-request-common-name cloud.migration.ora \
--nodes externalip-validation-webhook-service.externalip-validation-system.svc,\
externalip-validation-webhook-service.externalip-validation-system.svc.cluster.local \
--byo-ca-cert /etc/olcne/configs/certificates/production/ca.cert \
--byo-ca-key /etc/olcne/configs/certificates/production/ca.key \
--one-cert
```

権限の設定を下記で行う。

```bash
sudo chown -R opc:opc /etc/olcne/certificates/restrict_external_ip/production
```

サービスが実行されているか、下記のコマンドで確認。

```bash
systemctl status olcne-api-server.service 
```

## Platform API Serverを起動

オペレーターノードで、`/etc/olcne/bootstrap-olcne.sh`を使用して、証明書を使用するようにPlatform API Serverを構成する。

```bash
sudo /etc/olcne/bootstrap-olcne.sh \
--secret-manager-type file \
--olcne-component api-server \
--olcne-node-cert-path /etc/olcne/configs/certificates/production/node.cert \
--olcne-ca-path /etc/olcne/configs/certificates/production/ca.cert \
--olcne-node-key-path /etc/olcne/configs/certificates/production/node.key
```

## agentを起動

コントロールプレーンとワーカーで、下のコマンドを実行してagentを起動する。

```bash
sudo /etc/olcne/bootstrap-olcne.sh \
--secret-manager-type file \
--olcne-component agent \
--olcne-node-cert-path /etc/olcne/configs/certificates/production/node.cert \
--olcne-ca-path /etc/olcne/configs/certificates/production/ca.cert \
--olcne-node-key-path /etc/olcne/configs/certificates/production/node.key
```

# OCNE環境の作成

オペレーターノードで実施。
下記のコマンドで作成する。

```bash
olcnectl environment create \
--api-server 127.0.0.1:8091 \
--environment-name myenvironment \
--secret-manager-type file \
--olcne-node-cert-path /etc/olcne/configs/certificates/production/node.cert \
--olcne-ca-path /etc/olcne/configs/certificates/production/ca.cert \
--olcne-node-key-path /etc/olcne/configs/certificates/production/node.key \
--update-config
```

# Kubernetesモジュールのインストール

## 作業概要

- プライベートコンテナレジストリの利用設定
- cri-o, kubeletのインストールと設定
- Kubernetesモジュールの作成
- Kubernetesモジュールの検証
- Kubernetesモジュールのインストール

## プライベートコンテナレジストリの利用設定

コントロールプレーンとワーカーノードで、`/etc/container/registries.conf`を下記のように編集する。

```
# unqualified-search-registries = ["container-registry.oracle.com", "docker.io"]

# 設定例: HTTPを許可するコンテナレジストリ（ポート5000）
[[registry]]
prefix = "mirror.migration.ora:5000/olcne"
location = "mirror.migration.ora:5000/olcne"
insecure = true

short-name-mode = "permissive"
```

## cri-o, kubeletのインストールと設定

まず、cri-o, kubeletを入れる。

```bash
sudo yum install -y cri-o kubelet
```

このままの設定ではcri-oは起動しないので、`/etc/crio/crio.conf`にある、`conmon_cgroup`の値を変更する。デフォルトではコメントアウトされているので、コメントアウトを外して下記のように設定。

```
conmon_cgroup = "pod"
```

設定後、cri-oを起動＆有効化する。

```bash
sudo systemctl start crio
sudo systemctl enable crio
```

このあと、kubeletを有効化。

```bash
sudo systemctl enable kubelet
```

## Kubernetesモジュールの作成

下記のコマンドでモジュールを作成。

```bash
olcnectl module create \
--environment-name myenvironment \
--module kubernetes \
--name mycluster \
--container-registry mirror.migration.ora:5000/olcne \
--load-balancer lb.migration.ora:6443 \
--control-plane-nodes sec-control-plane-1.migration.ora:8090,sec-control-plane-2.migration.ora:8090,sec-control-plane-3.migration.ora:8090 \
--worker-nodes sec-worker-1.migration.ora:8090,sec-worker-2.migration.ora:8090 \
--selinux enforcing \
--restrict-service-externalip-ca-cert /etc/olcne/certificates/restrict_external_ip/production/ca.cert \
--restrict-service-externalip-tls-cert /etc/olcne/certificates/restrict_external_ip/production/node.cert \
--restrict-service-externalip-tls-key /etc/olcne/certificates/restrict_external_ip/production/node.key
```

## Kubernetesモジュールの検証

下記のコマンドでモジュールの検証。

```bash
olcnectl module validate \
--environment-name myenvironment \
--name mycluster
```

## Kubernetesモジュールのインストール

下記のコマンドでモジュールをインストール。

```bash
olcnectl module install \
--environment-name myenvironment \
--name mycluster
```

# 備考

インストール時には関係ないが、もしかしたら`/etc/crio/crio.conf`を下記のように設定する必要があるかもしれない（ローカルレジストリを利用するため）のでメモ。

```
[crio]
  [crio.api]
  [crio.image]
    pause_image_auth_file = "/run/containers/0/auth.json"
    insecure_registries = ["mirror.migration.ora:5000/olcne"]
  [crio.metrics]
  [crio.network]
    plugin_dirs = ["/opt/cni/bin"]
  [crio.nri]
  [crio.runtime]
    cgroup_manager = "systemd"
    conmon = "/usr/bin/conmon"
    conmon_cgroup = "system.slice"
    manage_network_ns_lifecycle = true
    manage_ns_lifecycle = true
    selinux = true
    [crio.runtime.runtimes]
      [crio.runtime.runtimes.kata]
        runtime_path = "/usr/bin/kata-runtime"
        runtime_type = "oci"
      [crio.runtime.runtimes.runc]
        allowed_annotations = ["io.containers.trace-syscall"]
        monitor_cgroup = "system.slice"
        monitor_env = ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
        monitor_exec_cgroup = ""
        monitor_path = "/usr/bin/conmon"
        privileged_without_host_devices = false
        runtime_config_path = ""
        runtime_path = ""
        runtime_root = "/run/runc"
        runtime_type = "oci"
  [crio.stats]
  [crio.tracing]
```
