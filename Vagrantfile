Vagrant.configure("2") do |config|
  config.vm.box = "centos/8"
  config.vm.box_version = "1905.1"
  config.vm.network "private_network", ip: "192.168.50.4"

  config.vm.provision "file", source: "~/.ssh/id_rsa.pub", destination: "/tmp/me.pub"
  config.vm.provision "shell", inline: <<-SHELL
    # copy keys
    mkdir -p -m 700 /root/.ssh/
    cp /tmp/me.pub /root/.ssh/authorized_keys
    rm /tmp/me.pub

    # Install docker
    yum-config-manager  --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install docker-ce docker-ce-cli containerd.io --nobest -y
    systemctl enable docker
    systemctl start docker
  SHELL
end
