all: clean test uninstall_env build

install_dev_env:
	pipenv install --dev

uninstall_env:
	test ! $(shell pipenv --venv; echo $?) || pipenv --rm

install_build_env:
	pipenv install

test: install_dev_env
	AWS_DEFAULT_REGION=us-east-1 pipenv run pytest

build: install_build_env
	test ! -d build || rm -rf build
	mkdir build
	rsync -r \
		--no-compress \
		--prune-empty-dirs \
		--exclude 'build*' \
		--exclude 'bin*' \
		--include '*/' \
		--exclude '*_test.py' \
		--include '*.py' \
		--exclude '*' \
		./ ./build/
	rsync -r \
		--no-compress \
		--prune-empty-dirs \
		--exclude '*.pyc' \
		--exclude '*dist-info*' \
		--exclude "_pytest" \
		--exclude "pytest" \
		--exclude 'pip*' \
		--exclude 'setuptools*' \
		--exclude 'docutils' \
		--exclude 'packaging' \
		--exclude 'pkg_resources' \
		--exclude "easy_install.py" \
		$(shell pipenv --venv)/lib/python*/site-packages/ ./build/

clean: uninstall_env
	test ! -d build || rm -rf build
