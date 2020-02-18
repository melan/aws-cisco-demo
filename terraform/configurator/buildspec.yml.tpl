---
version: 0.2

env:
  variables:
    AWS_ACCOUNT_ID: "${account_id}"
    AWS_DEFAULT_REGION: "${region}"
    AWS_SDK_LOAD_CONFIG: true
    AWS_VPN_REGIONS: ""
    ROUTER_PRIVATE_IP: "127.0.0.1"
    ROUTER_DEFAULT_GW: "127.0.0.1"
    PRIVATE_ADDRESS_SPACE: "127.0.0.1/32"
    LOG_LEVEL: "${log_level}"

phases:
  install:
    commands:
      - yum install -y python3 unzip jq awscli openssh-clients
      - pip3 install ansible paramiko pipenv
  build:
    commands:
      - cd $CODEBUILD_SRC_DIR
      - find . -type f
      - ./run.sh
      - echo "Done"

