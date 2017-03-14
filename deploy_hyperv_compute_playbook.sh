#!/bin/bash
set -e
VSWITCH_NAME=$1
HYPERV_USERNAME=$2
HYPERV_PASSWORD=$3

NEUTRON_KEYSTONE_PASSWORD=$(python -c "import yaml; print(yaml.load(open('/etc/kolla/passwords.yml', 'rb'))['neutron_keystone_password'])")
NOVA_KEYSTONE_PASSWORD=$(python -c "import yaml; print(yaml.load(open('/etc/kolla/passwords.yml', 'rb'))['nova_keystone_password'])")
RABBITMQ_PASSWORD=$(python -c "import yaml; print(yaml.load(open('/etc/kolla/passwords.yml', 'rb'))['rabbitmq_password'])")
CONTROLLER_ADDR=$(python -c "import yaml; print(yaml.load(open('/etc/kolla/globals.yml', 'rb'))['kolla_internal_vip_address'])")
KEYSTONE_URL="http://$CONTROLLER_ADDR:35357/v3"
KEYSTONE_URL_V2="http://$CONTROLLER_ADDR:35357/v2.0"

MGMT_IP=$(sudo ip addr show eth0 | sed -n 's/^\s*inet \([0-9.]*\).*$/\1/p')

sudo ansible-playbook -i hyperv_inventory hyperv-compute.yml \
--extra-vars="glance_host=$CONTROLLER_ADDR neutron_host=$CONTROLLER_ADDR neutron_keystone_password=$NEUTRON_KEYSTONE_PASSWORD \
keystone_url=$KEYSTONE_URL rabbitmq_host=$MGMT_IP rabbitmq_password=$RABBITMQ_PASSWORD vswitch_name=$VSWITCH_NAME \
keystone_url_v2=$KEYSTONE_URL_V2 nova_keystone_password=$NOVA_KEYSTONE_PASSWORD hyperv_username=$HYPERV_USERNAME hyperv_password=$HYPERV_PASSWORD"
