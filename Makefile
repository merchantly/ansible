# Source: https://github.com/paulRbr/ansible-makefile
#
# ------------------
# ANSIBLE-MAKEFILE v0.13.0
# Run ansible commands with ease
# ------------------
#
# Copyright (C) 2017 Paul(r)B.r
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

##
# VARIABLES
##
distribution ?= ubuntu
version      ?= bionic
container_id ?= $(shell mktemp)
playbook   ?= main
env        ?= hosts.ini
mkfile_dir ?= $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ifeq ("$(wildcard $(mkfile_dir)pass.sh)", "")
	opts     ?= $(args)
else # Handle vault password if any
	ifeq ("$(shell $(mkfile_dir)pass.sh 2> /dev/null)", "")
		opts     ?= $(args)
	else
		opts     ?= $(args) --vault-password-file=$(mkfile_dir)pass.sh
	endif
endif
ifneq ("$(limit)", "")
	opts     := $(opts) --limit="$(limit)"
endif
ifneq ("$(tag)", "")
	opts     := $(opts) --tag="$(tag)"
endif

##
# TASKS
##
.PHONY: install
install: ## make install # Install roles dependencies
	@ansible-galaxy install --role-file="requirements.yml"

.PHONY: inventory
inventory: ## make inventory [provider=<ec2|gce...>] [env=hosts] # Download dynamic inventory from Ansible's contrib
	@wget https://raw.githubusercontent.com/ansible/ansible/devel/contrib/inventory/$(provider).py
	@chmod +x $(provider).py
	mv $(provider).py $(env)

.PHONY: lint
lint: ## make lint [playbook=setup] [env=hosts] [args=<ansible-playbook arguments>] # Check syntax of a playbook
	@env=$(env) ansible-playbook --inventory-file="$(env)" --syntax-check $(opts) "$(playbook).yml"

.PHONY: debug
debug: mandatory-host-param ## make debug host=hostname [env=hosts] [args=<ansible arguments>] # Debug a host's variable
	@env=$(env) ansible -i $(env) $(opts) -m setup $(host)
	@env=$(env) ansible --inventory-file="$(env)" $(opts) --module-name="debug" --args="var=hostvars[inventory_hostname]" $(host)

.PHONY: dry-run
dry-run: ## make dry-run [playbook=setup] [env=hosts] [tag=<ansible tag>] [limit=<ansible host limit>] [args=<ansible-playbook arguments>] # Run a playbook in dry run mode
	@env=$(env) ansible-playbook --inventory-file="$(env)" --diff --check $(opts) "$(playbook).yml"

.PHONY: run
run: ## make run [playbook=setup] [env=hosts] [tag=<ansible tag>] [limit=<ansible host limit>] [args=<ansible-playbook arguments>] # Run a playbook
	@env=$(env) ansible-playbook --inventory-file="$(env)" --diff $(opts) "$(playbook).yml"

group ?=all
.PHONY: list
list: ## make list [group=all] [env=hosts] # List hosts inventory
	@env=$(env) ansible --inventory-file="$(env)" $(group) --list-hosts

.PHONY: vault
vault: mandatory-file-param ## make vault file=/tmp/vault.yml [env=hosts] [args=<ansible-vault arguments>] # Edit or create a vaulted file
	@[ -f "$(file)" ] && env=$(env) ansible-vault $(opts) edit "$(file)" || \
	env=$(env) ansible-vault $(opts) create "$(file)"

.PHONY: console
console: ## make console [env=hosts] [args=<ansible-console arguments>] # Run an ansible console
	@env=$(env) ansible-console --inventory-file="$(env)" $(opts)

group ?=all
.PHONY: facts
facts: ## make facts [group=all] [env=hosts] [args=<ansible arguments>] # Gather facts from your hosts
	@env=$(env) ansible --module-name="setup" --inventory-file="$(env)" $(opts) --tree="out/" $(group)

.PHONY: cmdb
cmdb: ## make cmdb # Create HTML inventory report
	@ansible-cmdb "out/" > list-servers.html

.PHONY: bootstrap
bootstrap: ## make bootstrap # Install ansible (Debian/Ubuntu only)
	@sudo apt-get update \
		&& sudo apt-get install python3-pip git sshpass \
		&& sudo pip3 install --upgrade pip \
		&& sudo pip install --upgrade virtualenv \
		&& (test -d ~/python_virtualenvs || mkdir ~/python_virtualenvs) \
		&& (test -f ~/python_virtualenvs/ansible/bin/activate || virtualenv ~/python_virtualenvs/ansible) \
		&& . ~/python_virtualenvs/ansible/bin/activate \
		&& pip3 install --upgrade ansible ansible-modules-hashivault \
		&& echo "Run the following command in your shell to activate a virtual environment with the ansible installed:" \
    && echo ". ~/python_virtualenvs/ansible/bin/activate"

.PHONY: mandatory-host-param mandatory-file-param
mandatory-host-param:
	@[ ! -z $(host) ]
mandatory-file-param:
	@[ ! -z $(file) ]

test_prepare_docker:
		docker pull ${distribution}:${version}
		docker build --no-cache --rm --file=travis/Dockerfile.${distribution}-${version} --tag=${distribution}-${version}:ansible travis

test: test_prepare_docker test_run_docker test_run test_clean ## make test [distrubition=ubuntu] [version=bionic] # Run tests on dockered images

test_run_docker:
		@echo "container_id=${container_id}"
		docker run --detach --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --volume="${PWD}":/etc/ansible/roles/merchantly:rw ${distribution}-${version}:ansible > ${container_id}

test_run:
		docker exec "$(shell cat ${container_id})" env ANSIBLE_FORCE_COLOR=1 ansible-playbook --version
		docker exec "$(shell cat ${container_id})" env ANSIBLE_FORCE_COLOR=1 ansible-playbook -i /etc/ansible/roles/merchantly/travis/hosts.ini -v /etc/ansible/roles/merchantly/main.yml --syntax-check
		docker exec "$(shell cat ${container_id})" env ANSIBLE_FORCE_COLOR=1 SHELL=/bin/bash ansible-playbook -i /etc/ansible/roles/merchantly/travis/hosts.ini -v /etc/ansible/roles/merchantly/main.yml
		docker exec "$(shell cat ${container_id})" env ANSIBLE_FORCE_COLOR=1 SHELL=/bin/bash ansible-playbook -i /etc/ansible/roles/merchantly/travis/hosts.ini -v /etc/ansible/roles/merchantly/main.yml \
			| grep -q 'changed=0.*failed=0' \
			&& (echo 'Idempotence test: pass' && exit 0) \
			|| (echo 'Idempotence test: fail' && exit 1) \

test_clean:
		docker rm -f "$(shell cat ${container_id})"

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

