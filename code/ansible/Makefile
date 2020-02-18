all: clean test build

build:
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
		--include '*.yml' \
		--include '*.j2' \
		--include 'Pipfile*' \
		--include '*.sh' \
		--exclude '*' \
		./ ./build/

install_dev_env:
	pipenv install --dev

uninstall_env:
	test ! $(shell pipenv --venv; echo $?) || pipenv --rm

install_build_env:
	pipenv install

test: install_dev_env
	AWS_DEFAULT_REGION=us-east-1 pipenv run pytest

clean: uninstall_env
	test ! -d build || rm -rf build
