#!/usr/bin/env bash

set -e

IPField=${IPFIELD:-PrivateIpAddress}

CWD=$(cd "$(dirname "$0")" && pwd)

if [ -n "${INSTANCE_ID}" ]; then
  echo "Processing Instance ${INSTANCE_ID}"

  instance_info=$(aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query \
    "Reservations[*].Instances[*].{Instance: InstanceId, Name:Tags[?Key=='Name']|[0].Value, IP:${IPField}, VpcId:VpcId, State:State.Name, ProductCode: ProductCodes[0].ProductCodeId, ProductSource: ProductCodes[0].ProductCodeType, KeyName: KeyName}" | \
    jq '.[] | .[] | .IP + "," + .KeyName' -r)

  IFS=',' read -ra I <<< "${instance_info}"
  ip="${I[0]}"
  key_name="${I[1]}"

  cat <<INVENTORY > ./inventory
[vpn_router]
${ip}
INVENTORY

  echo "Processing instance ${INSTANCE_ID}. IP: ${ip}, Key: ${key_name}"
  echo "Inventory: "
  cat ./inventory

  aws secretsmanager get-secret-value --secret-id="${key_name}" | jq -r .SecretString > key
  chmod 600 key

  test -d group_vars || mkdir group_vars
  pipenv install
  "$(pipenv --venv)/bin/python3" "$CWD/custom_facts.py" > "group_vars/vpn_router.yml"

  test -d ~/.ssh || mkdir ~/.ssh
  while [ -z "$(ssh-keyscan -H "${ip}")" ]; do
    sleep 10
  done

  ssh-keyscan -H "${ip}" >> ~/.ssh/known_hosts

  ansible-playbook --private-key="$CWD/key" -i "$CWD/inventory" "$CWD/playbooks/site.yml" --limit "vpn_router"
else
  echo "INSTANCE_ID is unset. Skipping"
fi