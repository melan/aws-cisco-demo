all: install_deps build

YUM = /usr/bin/yum
APT = apt

IS_YUM := $(shell $(YUM) --version 2>/dev/null)
IS_APT := $(shell $(APT) --version 2>/dev/null)
TFENV_INSTALLED := $(shell tfenv --version 2>/dev/null)

ifdef IS_YUM
	INSTALL = $(YUM) install -y
else ifdef IS_APT
	INSTALL = $(APT) install -y
else
	exit 1
endif


install_deps:
	$(INSTALL) python3 rsync which git unzip
	pip3 install pipenv

ifdef TFENV_INSTALLED
install_terraform: install_deps
	(cd terraform && tfenv install)
else
install_terraform: install_deps
	git clone https://github.com/tfutils/tfenv.git ~/.tfenv
	ln -s ~/.tfenv/bin/* /usr/bin
	(cd terraform && tfenv install)
endif

terraform_init: install_terraform
	(cd ./terraform; \
		terraform init)

create_secret: install_terraform
	(cd ./terraform; \
		terraform plan -out terraform.tfplan -target="aws_secretsmanager_secret.router-ssh-key" && \
		terraform apply "terraform.tfplan")

refresh_code: build terraform_init
	(cd ./terraform; \
		terraform plan -out terraform.tfplan -target="module.configurator-artifacts" && \
		terraform apply "terraform.tfplan")

refresh_lambda: refresh_code
	(cd ./terraform; \
		terraform plan -out terraform.tfplan -target="module.configurator.aws_lambda_function.instance_filter" && \
		terraform apply "terraform.tfplan")

reimage_router:
	(cd ./terraform; \
		terraform taint module.transit-vpc.aws_instance.router[0] && \
		terraform plan -out terraform.tfplan && \
		terraform apply "terraform.tfplan")

deployment:
	(cd ./terraform; \
		terraform plan -out terraform.tfplan && \
		terraform apply "terraform.tfplan")
build:
	(cd ./code/ansible && $(MAKE))
	(cd ./code/instance-filter-lambda && $(MAKE))
