ipaddr := `ip -4 -j route get 2.2.2.2 | jq -r '.[] | .prefsrc'`
git-dir := '~/work/canonical/repos'
docker-sources := '''
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
'''

install-all: tailscale docker-apt docker immich node-exporter

default:
  just --list

[group('install')]
tailscale:
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale login
    sudo tailscale set --ssh
    sudo tailscale set --operator=$USER
    # From another device (info from tailscale UI):
    # ssh -t ubuntu@vienna "sudo -u ubuntu -i zsh -l"
    # ssh ubuntu@vienna.alai-rooster.ts.net
    sudo tailscale serve --bg http://10.64.223.160:80

[group('install')]
docker-apt:
    # Add Docker's official GPG key:
    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo "{{docker-sources}}" | sudo tee /etc/apt/sources.list.d/docker.sources

[group('install')]
docker:
    sudo apt update
    sudo apt install -y docker.io
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
    sudo usermod -aG docker $USER

[group('install')]
immich:
    # https://docs.immich.app/install/docker-compose
    mkdir -p ~/work/docker/immich-app
    cp -a {{git-dir}}/dotfiles/misc/immich-app/. ~/work/docker/immich-app/
    cd ~/work/docker/immich-app && sg docker -c "docker compose up -d"

[group('install')]
node-exporter: vienna-backup-disk
    # Tutorial (https://gist.github.com/nwesterhausen/d06a772cbf2a741332e37b5b19edb192)
    sudo useradd --no-create-home --shell /bin/false node_exporter
    cd
    wget https://github.com/prometheus/node_exporter/releases/download/v0.18.1/node_exporter-0.18.1.linux-amd64.tar.gz
    tar xvf node_exporter-0.18.1.linux-amd64.tar.gz
    sudo mv node_exporter-0.18.1.linux-amd64 /opt/node_exporter
    sudo chown -R node_exporter:node_exporter /opt/node_exporter
    sudo nano /etc/systemd/system/node_exporter.service
    """
    [Unit]
    Description=Node Exporter
    Wants=network-online.target
    After=network-online.target

    [Service]
    User=node_exporter
    Group=node_exporter
    Type=simple
    ExecStart=/opt/node_exporter/node_exporter --collector.systemd

    [Install]
    WantedBy=multi-user.target
    """
    sudo systemctl daemon-reload
    sudo systemctl start node_exporter && sudo journalctl -f --unit node_exporter
    
[group('command')]
update-server:
    sudo apt update && sudo apt upgrade -y
    cd ~/work/docker/immich-app && sg docker -c "docker compose pull && docker compose up -d"

vienna-backup-disk:
    # important so the backup disk is visible to node_exporter
    sudo setfacl -m u:node_exporter:x /media/ubuntu
    sudo setfacl -m u:node_exporter:x /media/ubuntu/Backup
    sudo -u node_exporter stat -f /media/ubuntu/Backup
    sudo systemctl daemon-reload && sudo systemctl restart node_exporter

[group('command')]
rsync:
    # https://francium.cc/blog/using-rsync-to-backup-mirror-drives/
    sudo cp ~/work/docker/immich-app/drive-mirroring /usr/local/bin/drive-mirroring
    sudo cp ~/work/docker/immich-app/drive-mirroring.service /etc/systemd/system/drive-mirroring.service
    sudo cp ~/work/docker/immich-app/drive-mirroring.timer /etc/systemd/system/drive-mirroring.timer
    chmod +x /usr/local/bin/drive-mirroring
    sudo systemctl enable drive-mirroring.timer
    systemctl status drive-mirroring.timer

# This command is intended to be run from another host to observe Immich with COS
[group('observability')]
cos-lite:
    # TODO
    - I had to update the docker-compose.yaml to expose the metrics port for the immich server: git commit these

