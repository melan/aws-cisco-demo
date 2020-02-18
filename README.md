# Demo of automatic provisioning and configuration of Cisco CSR 1000v

## How to provision

I would recommend to use a blank container for the experiments. Switch to a folder where 
this project is clonned into and run something like:

```bash
docker run -it --rm -v $PWD:/src -w /src \
    -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
        amazonlinux:2 /bin/bash
```

Just make sure you pass there correct values of the AWS access keys. 

### Generate SSH keys

```bash
ssh-keygen -t rsa -C <some_address@email.tld> -f cisco_demo
```

Create `terraform/terraform.tfvars` file. Simply use this template:

```ini
ssh-public-key        = "ssh-rsa AA..."
router-ssh-public-key = "ssh-rsa AA..."
deploy_router         = false
```

`ssh-public-key` and `router-ssh-public-key` are public ssh keys to ssh to test
instances deployed in every region and the key to ssh to the router. You can use the same
key for both of the variables or different ones. If you decide to use different keys for the variables
please make sure to use the right private later when you will provision a secret at AWS Secrets Manager.

`deploy_router` variable tells the system if the instance with the router should be provisioned.
I would recommend to run it first without the router instance and next time switch the variable to true.
The only reason to do so is to make sure all components of the configuration pipeline are there
and ready to configure the new instances. As an alternative you can later run `make reimage_router`
this command will trigger the reprovisioning of the router instance 

### Install `make`:
```bash
yum install make
```

### Create a secret for the private ssh key to the router:

```bash
make create_secret
```

After that Open AWS Console (https://console.aws.amazon.com/secretsmanager/home?region=us-east-1#/secret?name=cisco-demo-router-key) and put there 
the private key generated earlier 

### Upload code to S3

```bash
make refresh_code
```

This command creates zip files with code for the lambda function and with ansible playbooks and upload them to an s3
bucket from where the files can be downloaded later by lambda provisioning and by the CodeBuild job
 
### Deploy the project

```bash
make deploy
```

This command runs terraform against full body of manifests. Depending on values of the `deploy_router` variable 
mentioned above, this will command will or will not provision the router instance. It is highly recommended to 
run it first with `deploy_router=false` and only after that switch `deploy_router=true`.

The run may fail with this error:

```
Error launching source instance: OptInRequired: In order to use this AWS Marketplace product
you need to accept terms and subscribe. To do so please visit 
https://aws.amazon.com/marketplace/pp?sku=5tiyrfb5tasxk9gmnab39b843
```

Follow the link, accept the conditions and repeat the run. Don't forget to cancel the subscription when you are done.
The subscription is free because this project uses a BYOL image of the Cisco CSR.

### Destroy the infrastructure

When you are done with the experiments simply run:

```bash
cd terraform
terraform destroy
```

It will stop in the middle, will ask to type 'yes' and to press Enter.

## Useful links to track progress

https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:sort=instanceState - List all instances in the region with 
the Transit VPC

https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/cisco-demo-csr-config-instance-filter?tab=monitoring -
information about a Lambda that does filtering of the SNS messages about instances and triggers CodeBuild where 
a new Router instance is provisioned

https://us-east-1.console.aws.amazon.com/codesuite/codebuild/projects/cisco-demo-csr-config-cisco-csr-configurator/history?region=us-east-1 - 
CodeBuild project responsible for configuration of the router

https://us-east-2.console.aws.amazon.com/vpc/home?region=us-east-2#VpnConnections:sort=VpnConnectionId - list of all 
VPN Connections in the region. After the router is configured - wait a bit and you will see tunnels there will start
switching from DOWN to UP, and it will show that there are some BGP routes propagated over the VPN connection 
