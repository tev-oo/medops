
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-13"
  config.vm.hostname = "medops-node01"

  # Do not automatically mount the MedOps source tree,
  # including local .env secrets, inside the VM.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider "virtualbox" do |vb|
    vb.name = "medops-node01"
    vb.cpus = 2
    vb.memory = 4096
    vb.gui = false
  end

  config.ssh.insert_key = true
end

