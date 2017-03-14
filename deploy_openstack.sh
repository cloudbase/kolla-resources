#!/bin/bash
set -e

MGMT_IP=10.101.0.249
MGMT_NETMASK=255.255.0.0
MGMT_GATEWAY=10.101.101.1
MGMT_DNS="8.8.8.8 8.8.4.4"

FIP_START=10.101.64.2
FIP_END=10.101.64.200
FIP_GATEWAY=10.101.4.1
FIP_CIDR=10.101.0.0/16
TENANT_NET_DNS="8.8.8.8 8.8.4.4"

KOLLA_INTERNAL_VIP_ADDRESS=10.101.231.254

KOLLA_BRANCH=stable/newton
KOLLA_OPENSTACK_VERSION=3.0.2

DOCKER_NAMESPACE=cloudbaseit

sudo tee /etc/network/interfaces <<EOF
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet static
address $MGMT_IP
netmask $MGMT_NETMASK
gateway $MGMT_GATEWAY
dns-nameservers $MGMT_DNS

auto eth1
iface eth1 inet manual
up ip link set \$IFACE up
up ip link set \$IFACE promisc on
down ip link set \$IFACE promisc off
down ip link set \$IFACE down

auto eth3
iface eth3 inet manual
up ip link set \$IFACE up
up ip link set \$IFACE promisc on
down ip link set \$IFACE promisc off
down ip link set \$IFACE down
EOF

for iface in eth0 eth1 eth3
do
    sudo ifdown $iface || true
    sudo ifup $iface
done

# Get Docker and Ansible
sudo apt-add-repository ppa:ansible/ansible -y
sudo apt-get update
sudo apt-get install -y docker.io ansible

# NTP client
sudo apt-get install -y ntp

# Install Kolla
cd ~
git clone https://github.com/openstack/kolla -b $KOLLA_BRANCH
sudo apt-get install -y python-pip
sudo pip install ./kolla
sudo cp -r kolla/etc/kolla /etc/

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/kolla.conf <<-'EOF'
[Service]
MountFlags=shared
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# Get the container images for the OpenStack services
sudo sed -i '/#kolla_base_distro/i kolla_base_distro: "ubuntu"' /etc/kolla/globals.yml
sudo sed -i '/#docker_namespace/i docker_namespace: "'$DOCKER_NAMESPACE'"' /etc/kolla/globals.yml
sudo sed -i '/#openstack_release/i openstack_release: "'$KOLLA_OPENSTACK_VERSION'"' /etc/kolla/globals.yml
sudo kolla-ansible pull


sudo sed -i 's/^kolla_internal_vip_address:\s.*$/kolla_internal_vip_address: "'$KOLLA_INTERNAL_VIP_ADDRESS'"/g' /etc/kolla/globals.yml
sudo sed -i '/#network_interface/i network_interface: "eth0"' /etc/kolla/globals.yml
sudo sed -i '/#neutron_external_interface/i neutron_external_interface: "eth1"' /etc/kolla/globals.yml

sudo mkdir -p /etc/kolla/config/neutron

sudo tee /etc/kolla/config/neutron/ml2_conf.ini <<-'EOF'
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan,vlan
mechanism_drivers = openvswitch,hyperv
extension_drivers = port_security
[ml2_type_vlan]
network_vlan_ranges = physnet2:500:2000
[ovs]
bridge_mappings = physnet1:br-ex,physnet2:br-data
EOF

# kolla-ansible prechecks fails if the hostname in the hosts file is set to 127.0.1.1
MGMT_IP=$(sudo ip addr show eth0 | sed -n 's/^\s*inet \([0-9.]*\).*$/\1/p')
sudo bash -c "echo $MGMT_IP $(hostname) >> /etc/hosts"

# Generate random passwords for all OpenStack services
sudo kolla-genpwd

sudo kolla-ansible prechecks -i kolla/ansible/inventory/all-in-one
sudo kolla-ansible deploy -i kolla/ansible/inventory/all-in-one
sudo kolla-ansible post-deploy -i kolla/ansible/inventory/all-in-one

sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-br br-data
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data eth3
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-data phy-br-data || true
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data type=patch
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl add-port br-int int-br-data || true
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data type=patch
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface phy-br-data options:peer=int-br-data
sudo docker exec --privileged openvswitch_vswitchd ovs-vsctl set interface int-br-data options:peer=phy-br-data


# Remove unneeded Nova containers
for name in nova_compute nova_ssh nova_libvirt
do
    for id in $(sudo docker ps -q -a -f name=$name)
    do
        sudo docker stop $id
        sudo docker rm $id
    done
done


#sudo add-apt-repository cloud-archive:newton -y && apt-get update
sudo apt-get install -y python-openstackclient

source /etc/kolla/admin-openrc.sh

wget https://cloudbase.it/downloads/cirros-0.3.4-x86_64.vhdx.gz
gunzip cirros-0.3.4-x86_64.vhdx.gz
openstack image create --public --property hypervisor_type=hyperv --disk-format vhd --container-format bare --file cirros-0.3.4-x86_64.vhdx cirros-gen1-vhdx
rm cirros-0.3.4-x86_64.vhdx

# Create the private network
neutron net-create private-net --provider:physical_network physnet2 --provider:network_type vlan
neutron subnet-create private-net 10.10.10.0/24 --name private-subnet --allocation-pool start=10.10.10.50,end=10.10.10.200 --dns-nameservers list=true $TENANT_NET_DNS --gateway 10.10.10.1

# Create the public network
neutron net-create public-net --shared --router:external --provider:physical_network physnet1 --provider:network_type flat
neutron subnet-create public-net --name public-subnet --allocation-pool start=$FIP_START,end=$FIP_END --disable-dhcp --gateway $FIP_GATEWAY $FIP_CIDR

# create a router and hook it the the networks
neutron router-create router1

neutron router-interface-add router1 private-subnet
neutron router-gateway-set router1 public-net

