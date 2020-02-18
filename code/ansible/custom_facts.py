#!/usr/bin/env python3

import logging
import os
import sys
from typing import List, NewType, Optional, Tuple

import boto3
import ipaddress
import xmltodict
import traceback
import yaml


IP = NewType('IP', str)


logger = logging.getLogger(os.environ.get('CODEBUILD_BUILD_ID', "CODEBUILD"))
logger.setLevel(int(os.environ.get('LOG_LEVEL', logging.INFO)))
handler = logging.StreamHandler(sys.stderr)
formatter = logging.Formatter('[%(levelname)s - %(name)s] %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.propagate = False

ssm = boto3.client('ssm')


def noop(self, *args, **kw):
    pass


# Suppress type tags in YAML
yaml.emitter.Emitter.process_tag = noop


class CIDR(object):
    def __init__(self, cidr: str, gen_hosts: bool = False):
        self.cidr = cidr

        ip_network = ipaddress.ip_network(str(cidr), strict=False)
        self.hosts = [str(h) for h in ip_network.hosts()] if gen_hosts else []
        self.network_address = str(ip_network.network_address)
        self.netmask = str(ip_network.netmask)
        self.hostmask = str(ip_network.hostmask)

    def __str__(self):
        return self.cidr


class VPNClientGateway(object):
    vpn_id: str
    remote_address: IP
    in_tunnel_network: CIDR
    in_tunnel_network: CIDR
    in_tunnel_ip1: IP
    in_tunnel_ip2: IP
    preshared_key: str
    asn: int

    def __init__(self, vpn_id: str, remote_address: IP, in_tunnel_network: Optional[CIDR],
                 preshared_key: str, asn: int):
        self.vpn_id = vpn_id
        self.remote_address = remote_address
        self.in_tunnel_network = in_tunnel_network

        if in_tunnel_network is not None:
            self.in_tunnel_neighbor = IP(str(in_tunnel_network.hosts[0]))
            self.in_tunnel_router = IP(str(in_tunnel_network.hosts[1]))

        self.preshared_key = preshared_key
        self.asn = asn


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
            if type(v) == CIDR:
                network = ipaddress.ip_network(v.cidr, strict=False)
            else:
                network = ipaddress.ip_network(v, strict=False)

            if fail_on_32_network and network.prefixlen == 32:
                raise ValueError("%s can't be /32 network")

        except ValueError as err:
            raise ValueError("Error in %s: %s" % (k, err))

    return True


def extract_gateways_configuration(customer_gateway_configuration: str) -> List[VPNClientGateway]:
    parsed_config = xmltodict.parse(customer_gateway_configuration)

    vpn_client_gateways: List[VPNClientGateway] = []

    vpn_id = parsed_config['vpn_connection']['@id']
    for i in range(len(parsed_config['vpn_connection']['ipsec_tunnel'])):
        tunnel = parsed_config['vpn_connection']['ipsec_tunnel'][i]
        tunnel_config = VPNClientGateway(
            vpn_id="{vpn_id}-{tunnel_id}".format(vpn_id=vpn_id, tunnel_id=i),
            remote_address=tunnel['vpn_gateway']['tunnel_outside_address']['ip_address'],
            in_tunnel_network=CIDR("{network_address}/{network_cidr}".format(
                network_address=tunnel['customer_gateway']['tunnel_inside_address']['ip_address'],
                network_cidr=tunnel['customer_gateway']['tunnel_inside_address']['network_cidr']),
                gen_hosts=True),
            preshared_key=tunnel['ike']['pre_shared_key'],
            asn=tunnel['vpn_gateway']['bgp']['asn']
        )
        vpn_client_gateways.append(tunnel_config)

    return vpn_client_gateways


def extract_router_asn(customer_gateway_configuration) -> Optional[str]:
    parsed_config = xmltodict.parse(customer_gateway_configuration)

    for tunnel in parsed_config['vpn_connection']['ipsec_tunnel']:
        return tunnel['customer_gateway']['bgp']['asn']

    return None


def discover_aws_vpn_connections(ec2_client) -> Tuple[List[VPNClientGateway], str]:
    vpn_connections = ec2_client.describe_vpn_connections(Filters=[
        {'Name': 'state', 'Values': ['available']},
        {'Name': 'type', 'Values': ['ipsec.1']}
    ])

    vpn_client_gateways: List[VPNClientGateway] = []
    router_asn = None
    for vpn_connection in vpn_connections['VpnConnections']:
        customer_gateway_configuration = vpn_connection['CustomerGatewayConfiguration']
        vpn_client_gateways.extend(extract_gateways_configuration(customer_gateway_configuration))
        if router_asn is None:
            router_asn = extract_router_asn(customer_gateway_configuration)

    if router_asn is None:
        router_asn = '65000'

    return vpn_client_gateways, router_asn


def generate_cisco_config_facts(aws_regions: List[str],
                                router_private_ip: IP,
                                router_default_gw: IP,
                                private_address_space: CIDR):
    # discover all AWS VPN endpoints
    vpns: List[VPNClientGateway] = []
    router_asn = None

    for region in aws_regions:
        ec2_client = boto3.client('ec2', region_name=region)
        new_vpns, new_router_asn = discover_aws_vpn_connections(ec2_client=ec2_client)
        if router_asn is None:
            router_asn = new_router_asn

        vpns.extend(new_vpns)

    # generate final configuration
    validate_ip_addresses(local_address=router_private_ip, default_gw=router_default_gw)
    validate_ip_networks(private_address_space=private_address_space, fail_on_32_network=True)

    if router_asn is None:
        router_asn = '65000'

    return dict(
        vpns=vpns,
        local_address=router_private_ip,
        default_gw=router_default_gw,
        private_address_space=private_address_space,
        router_asn=router_asn
    )


def main():
    logger.info("Generating Cisco config")

    try:
        config = generate_cisco_config_facts(aws_regions=os.environ['AWS_VPN_REGIONS'].split(','),
                                             router_private_ip=IP(os.environ['ROUTER_PRIVATE_IP']),
                                             router_default_gw=IP(os.environ['ROUTER_DEFAULT_GW']),
                                             private_address_space=CIDR(os.environ['PRIVATE_ADDRESS_SPACE']))

        opts = dict(indent=4, stream=sys.stdout)
        yaml.dump(config, **opts)
    except Exception as ex:
        trace = traceback.format_exc()

        logger.error("Unable to generate a configuration for Cisco because of an error: {error}\n{trace}".format(
            error=str(ex), trace=trace))
        sys.exit(1)


if __name__ == "__main__":
    main()
