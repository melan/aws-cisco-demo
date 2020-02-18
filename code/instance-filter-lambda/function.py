#!/usr/bin/env python3

import logging
import os
import sys
from typing import List, NewType, NamedTuple

import boto3
import ipaddress
import json
import traceback

IP = NewType('IP', str)
CIDR = NewType('CIDR', str)


'''
Configuration:
    Environment variables:
        - AWS_LAMBDA_FUNCTION_NAME
        - LAMBDA_LOG_LEVEL. Default: INFO
        - INSTANCE_PRODUCT_CODE - product code for the AMI from marketplace
        - INSTANCE_PRODUCT_SOURCE - marketplace
        - INSTANCE_VPC_ID - VPC where the instance is running
        - BUILD_PROJECT - name of the build project
'''

log_level = int(os.environ.get('LAMBDA_LOG_LEVEL', logging.INFO))
logger = logging.getLogger(os.environ.get('AWS_LAMBDA_FUNCTION_NAME', "AWS Lambda"))
logger.setLevel(log_level)
handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter('[%(levelname)s - %(name)s] %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.propagate = False

sts = boto3.client('sts')
ec2 = boto3.client('ec2')
ec2_resource = boto3.resource('ec2')
codebuild = boto3.client('codebuild')

InstanceId = NamedTuple("InstanceId", [
    ("region", str),
    ("instance_id", str),
    ("account_id", str),
    ("state", str)
])

InstanceInfo = NamedTuple("InstanceInfo", [
    ("instance_id", str),
    ("name", str),
    ("private_ip", str),
    ("product_code", str),
    ("product_source", str),
    ("state", str),
    ("vpc_id", str),
    ("key_name", str),
    ("default_gw", str)
])


def validate_ip_addresses(**kwargs):
    for k, v in kwargs.items():
        try:
            ipaddress.ip_address(v)
        except ValueError as err:
            raise ValueError("Error in %s: %s" % (k, err))

    return True


def validate_ip_networks(fail_on_32_network=False, **kwargs):
    for k, v in kwargs.items():
        try:
            network = ipaddress.ip_network(v, strict=False)
            if fail_on_32_network and network.prefixlen == 32:
                raise ValueError("%s can't be /32 network")

        except ValueError as err:
            raise ValueError("Error in %s: %s" % (k, err))

    return True


def parse_event(event) -> List[InstanceId]:
    instances = []
    for e in event["Records"]:
        message = json.loads(e["Sns"]["Message"])

        region = message["region"]
        instance_id = message["detail"]["instance-id"]
        account_id = message["account"]
        state = message["detail"]["state"]

        instances.append(InstanceId(region=region, instance_id=instance_id, account_id=account_id, state=state))

    return instances


def parse_instance_info(describe_instance_info: dict) -> InstanceInfo:
    instance_id = describe_instance_info["InstanceId"]
    private_ip = describe_instance_info["PrivateIpAddress"]
    vpc_id = describe_instance_info["VpcId"]
    state = describe_instance_info["State"]["Name"]
    key_name = describe_instance_info["KeyName"]
    subnet_id = describe_instance_info["SubnetId"]

    # get default gateway for the instance
    try:
        subnet = ec2_resource.Subnet(subnet_id)
        subnet.load()
        subnet_cidr = subnet.cidr_block

        default_gw = str(list(ipaddress.ip_network(subnet_cidr).hosts())[0])
    except Exception as ex:
        raise RuntimeError("Can't figure out default gateway for instance %s with private ip %s: %s" % (
            instance_id, private_ip, ex
        ))

    name = [t["Value"] for t in describe_instance_info["Tags"] if t["Key"] == "Name"]
    product_code = [t["ProductCodeId"] for t in describe_instance_info["ProductCodes"]]
    product_source = [t["ProductCodeType"] for t in describe_instance_info["ProductCodes"]]

    name = "" if len(name) == 0 else name[0]
    product_code = "" if len(product_code) == 0 else product_code[0]
    product_source = "" if len(product_source) == 0 else product_source[0]

    instance_info = InstanceInfo(instance_id=instance_id,
                                 name=name,
                                 private_ip=private_ip,
                                 product_code=product_code,
                                 product_source=product_source,
                                 state=state,
                                 vpc_id=vpc_id,
                                 key_name=key_name,
                                 default_gw=default_gw)
    return instance_info


def is_valid_instance_id(instance_id: InstanceId, account_id: str, region: str) -> bool:
    if instance_id.account_id != account_id:
        logger.info("Skipping %s because account_id doesn't match: Expected: '%s', Actual: '%s'" %
                    (instance_id.instance_id, account_id, instance_id.account_id))
        return False

    if instance_id.state != "running":
        logger.info("Skipping %s because the state isn't running: Expected: '%s', Actual: '%s'" %
                    (instance_id.instance_id, "running", instance_id.state))
        return False

    if instance_id.region != region:
        logger.info("Skipping %s because the region doesn't match: Expected: '%s', Actual: '%s'" %
                    (instance_id.instance_id, region, instance_id.region))
        return False

    return True


def is_valid_instance(instance_info: InstanceInfo, product_code: str, product_source: str, vpc_id: str) -> bool:
    private_ip_valid = True
    try:
        ipaddress.ip_address(instance_info.private_ip)
    except:
        private_ip_valid = False

    if instance_info.private_ip == "" or instance_info.private_ip is None or not private_ip_valid:
        logger.info("Skipping %s because private ip is invalid: '%s'" %
                    (instance_info.instance_id, instance_info.private_ip))
        return False

    if instance_info.product_code != product_code:
        logger.info("Skipping %s because product_code doesn't match: Expected: '%s', Actual: '%s'" %
                    (instance_info.instance_id, product_code, instance_info.product_code))
        return False

    if instance_info.product_source != product_source:
        logger.info("Skipping %s because product source doesn't match: Expected: '%s', Actual: '%s'" %
                    (instance_info.instance_id, product_source, instance_info.product_source))
        return False

    if instance_info.vpc_id != vpc_id:
        logger.info("Skipping %s because vpc_id doesn't match: Expected: '%s', Actual: '%s'" %
                    (instance_info.instance_id, vpc_id, instance_info.vpc_id))
        return False

    return True


def handler(event, context):
    logger.debug("Event: {event}".format(event=event))

    try:
        logger.debug("Getting account id")
        aws_caller_identity = sts.get_caller_identity()
        account_id = aws_caller_identity["Account"]
        logger.debug("Current account is %s" % account_id)

        region = os.environ["AWS_REGION"]
        product_code = os.environ["INSTANCE_PRODUCT_CODE"]
        product_source = os.environ["INSTANCE_PRODUCT_SOURCE"]
        vpc_id = os.environ["INSTANCE_VPC_ID"]
        build_project = os.environ["BUILD_PROJECT"]
        aws_vpn_regions = os.environ["AWS_VPN_REGIONS"]
        private_address_space = os.environ["PRIVATE_ADDRESS_SPACE"]

        logger.debug(("Other parameters: region: {region}, vpc_id: {vpc_id}, product_code: {code}, " +
                      "product_source: {source}, build_project: {build_project}").format(
            region=region, vpc_id=vpc_id, code=product_code, source=product_source, build_project=build_project)
        )

        # get region and instance id info from the message
        instance_ids = parse_event(event)
        logger.debug("Processing instances: %s" % instance_ids)

        # pull information about the instance
        ids = [instance_id.instance_id for instance_id in instance_ids
               if is_valid_instance_id(instance_id, account_id=account_id, region=region)]

        logger.debug("Matching instances: %s" % ids)

        if len(ids) == 0:
            logger.info("No instances left to process. Skipping")
            return {
                "status": 200,
                "message": "No instances left"
            }

        describe_resp = ec2.describe_instances(InstanceIds=ids)
        for reservation in describe_resp["Reservations"]:
            for instance in reservation["Instances"]:
                instance_info = parse_instance_info(instance)
                logger.debug("Processing instance %s/%s" % (instance_info.instance_id, instance_info.name))
                # validate that the instance is our router
                if not is_valid_instance(instance_info=instance_info, product_code=product_code,
                                         product_source=product_source, vpc_id=vpc_id):
                    continue

                # generate config and run ansible to update it
                logger.debug("Let's run CodeBuild for %s/%s" % (instance_info.instance_id, instance_info.private_ip))
                codebuild_resp = codebuild.start_build(projectName=build_project, environmentVariablesOverride=[
                    {'name': 'INSTANCE_ID', 'value': instance_info.instance_id, 'type': 'PLAINTEXT'},
                    {'name': 'LOG_LEVEL', 'value': str(log_level), 'type': 'PLAINTEXT'},
                    {'name': 'AWS_VPN_REGIONS', 'value': aws_vpn_regions, 'type': 'PLAINTEXT'},
                    {'name': 'ROUTER_PRIVATE_IP', 'value': instance_info.private_ip, 'type': 'PLAINTEXT'},
                    {'name': 'ROUTER_DEFAULT_GW', 'value': instance_info.default_gw, 'type': 'PLAINTEXT'},
                    {'name': 'PRIVATE_ADDRESS_SPACE', 'value': private_address_space, 'type': 'PLAINTEXT'}
                ])

                logger.debug("CodeBuild for %s/%s is done: %s" % (instance_info.instance_id, instance_info.private_ip,
                                                                  codebuild_resp))

        return {
            "status": 200,
            "message": "OK"
        }

    except Exception as ex:
        logger.error("Something went wrong with the Cisco config generator: %s" % ex)
        logger.error(traceback.format_exc())
        return {
            "status": 500,
            "message": "Something is wrong. Check logs"
        }

