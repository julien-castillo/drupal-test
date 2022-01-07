OS_INFORMATION=$(shell uname -s)
ifneq (,$(findstring Linux,$(OS_INFORMATION)))
	OS_NAME = linux
endif

ifneq (,$(findstring Darwin,$(OS_INFORMATION)))
	OS_NAME = mac
endif

ifneq (,$(findstring CYGWIN,$(OS_INFORMATION)))
	OS_NAME = win
endif

ifneq (,$(findstring MINGW,$(OS_INFORMATION)))
	OS_NAME = win
endif

DOCKER_COMPOSE_FILES := -f docker-compose.yml
ifneq ("$(wildcard docker-compose-${OS_NAME}.yml)","")
	DOCKER_COMPOSE_FILES := $(DOCKER_COMPOSE_FILES) -f docker-compose-${OS_NAME}.yml
endif

ifneq ("$(wildcard docker-compose-local.yml)","")
	DOCKER_COMPOSE_FILES := $(DOCKER_COMPOSE_FILES) -f docker-compose-local.yml
endif

DOCKER_COMPOSE = docker-compose ${DOCKER_COMPOSE_FILES}
EXEC_PHP = $(DOCKER_COMPOSE) exec -T php
DRUPAL_CONSOLE = $(EXEC_PHP) drupal
DRUSH = $(EXEC_PHP) drush
COMPOSER = $(EXEC_PHP) composer
#PROFILE = ccifr_v1_local
PROFILE = cci_local_v1
# MODULE =

.env:
ifeq (,$(wildcard ./.env))
	cp .env.dist .env
endif

##
## Project
## -------
##

build: ## Build project dependencies.
build: start
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/build.sh"

kill: ## Kill all docker containers.
kill:
	$(DOCKER_COMPOSE) kill
	$(DOCKER_COMPOSE) down --volumes --remove-orphans

install: ## Start docker stack and install the project.
install: start
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/install.sh $(PROFILE)"
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/reset_password.sh"

update: ## Start docker stack and update the project.
update: start
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/update.sh $(PROFILE)"

setup:  ## Start docker stack, build and install the project.
setup: .env build install

reset: ## Kill all docker containers and start a fresh install of the project.
reset: kill setup

start: .env update-permissions ## Start the project.
	$(DOCKER_COMPOSE) up -d --remove-orphans
	$(DOCKER_COMPOSE) exec -u 0 php sh -c "if [ -d /var/www/html/docroot/sites/default ]; then chmod -R a+w /var/www/html/docroot/sites/default; fi"
	$(DOCKER_COMPOSE) exec -u 0 php sh -c "if [ -d /tmp/cache ]; then chmod -R a+w /tmp/cache; fi"


reset_password: ## Reset the Drupal password to "admin".
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/reset_password.sh"

update-permissions: ## Fix permissions between Docker and the host.
ifeq ($(OS_NAME), linux)
update-permissions:
	sudo setfacl -dR -m u:$(shell whoami):rwX -m u:82:rwX -m u:1000:rwX .
	sudo setfacl -R -m u:$(shell whoami):rwX -m u:82:rwX -m u:1000:rwX .
else ifeq ($(OS_NAME), mac)
update-permissions:
	sudo dseditgroup -o edit -a $(shell id -un) -t user $(shell id -gn 82)
endif

stop: ## Stop all docker containers.
	$(DOCKER_COMPOSE) stop

clean: ## Kill all docker containers and remove generated files
clean: kill
	rm -rf .env vendor docroot/core docroot/modules/contrib docroot/themes/contrib docroot/profiles/contrib

ifeq (console,$(firstword $(MAKECMDGOALS)))
  CONSOLE_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(CONSOLE_ARGS):;@:)
endif
console: ## Open a console in the container passed in argument (e.g make console php)
	$(DOCKER_COMPOSE) exec $(CONSOLE_ARGS) bash

reboot: ## Stop and start the project.
reboot: stop start

webapp: ## make a webapp initiales
webapp:
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/webapp.sh $(name)"

.PHONY: build setup kill install update reset reset_password start stop clean console update-permissions drush reboot

##
## Utils
## -----
##

drush: ## Execute a drush command inside PHP container (e.g: make drush cmd="cache:rebuild").
	$(DRUSH) $(cmd)

drupal: ## Execute a drupal-console command inside PHP container (e.g: make drupal cmd="generate:module")
	$(DRUPAL_CONSOLE) $(cmd)

enable-all-webapps: ## Enable all CCI WebApps.
	$(DRUSH) en \
	webapp_actualite \
	webapp_agence \
	webapp_article \
	webapp_carrefour \
	webapp_commerce \
	webapp_cci_connect \
	webapp_contact \
	webapp_hipay \
	webapp_cci_store_banner \
	webapp_compte_client \
	webapp_simple_content \
	webapp_crm_edeal_aura \
	webapp_etablissement \
	webapp_evenement \
	webapp_formulaire \
	webapp_generateur_pdf \
	webapp_newsletter \
	webapp_produit \
	webapp_search \
	webapp_rss \
	webapp_social \
	webapp_widget_cci_store \
	webapp_workflow

logs: ## Show Drupal logs.
	$(DRUSH) ws

cr: ## Rebuild Drupal caches.
	$(DRUSH) cache:rebuild

cex: ## Export Drupal configuration.
	$(DRUSH) config-split:export -y

sex: ## Staging export.
	$(DRUSH) export-content

sim: ## Staging import.
	$(DRUSH) update-migration-config && $(DRUSH) migrate:import --group=entity_staging

clear-db: ## Truncate some tables.
	$(DRUSH) sql:query --file=/var/www/html/automation/bin/clear.sql && $(DRUSH) cache:rebuild

import-bdd: ## Import an ACQUIA database. (e.g: make import-bdd database="database.sql" password="admin").
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/import-bdd.sh $(database) $(password)"

ifeq (composer,$(firstword $(MAKECMDGOALS)))
  COMPOSER_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(COMPOSER_ARGS):;@:)
endif
composer: ## Execute a composer command inside PHP container (e.g: make composer require drupal/paragraphs).
	$(COMPOSER) $(COMPOSER_ARGS)

.PHONY: logs cr cex composer clear-db import-bdd

npm_logs: ## Show NPM logs.
	$(DOCKER_COMPOSE) logs --tail="20" -f npm

npm-install: ## Install NPM dependencies.
	$(DOCKER_COMPOSE) run --rm npm npm install

npm-install-module: ## Install new NPM dependency (e.g: make npm-istall module="")
	$(DOCKER_COMPOSE) run --rm npm npm install $(module)

npm-upgrade: ## Upgrade NPM dependencies.
	$(DOCKER_COMPOSE) run --rm npm npm upgrade

npm-start: ## Start NPM.
	$(DOCKER_COMPOSE) run --rm npm npm start

npm-watch: ## Run "watch" command for NPM.
	$(DOCKER_COMPOSE) run --rm npm npm run watch

.PHONY: npm_logs npm-start npm-watch

field-migration-run: ## Run field migrations. (e.g: make field-migration-test user='acquia_username' api_key='acquia_api_key' env='dev')
	./automation/bin/field_migration/download-databases.sh $(user) $(api_key) $(env) && \
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/field_migration/field-migrations-run.sh $(PROFILE)"
	./automation/bin/field_migration/clean-databases.sh

field-migration-migrate: ## Execute migration commands
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/field_migration/field-migration-migrate.sh"

field-migration-test: ## Test field migrations
	$(DOCKER_COMPOSE) exec php sh -c "./automation/bin/field_migration/field-migration-test.sh"

.PHONY: field-migration-run field-migration-migrate field-migration-test

##
## Quality assurance
## -----------------
##
phpcs: ## Run PHP Code Sniffer using the phpcs.xml.dist ruleset.
	$(DOCKER_COMPOSE) -f docker-compose-tools.yml run --rm php_quality_tools phpcs --standard=phpcs.xml.dist

phpstan: ## Run PHPStan using the phpstan.neon.dist ruleset.
	$(DOCKER_COMPOSE) -f docker-compose-tools.yml run --rm php_quality_tools phpstan analyse --memory-limit=-1 ./docroot/modules/custom ./docroot/themes/custom ./docroot/profiles/custom

phpmd: ## Run PHP Mess Detector using the phpmd.rules.xml ruleset.
	$(DOCKER_COMPOSE) -f docker-compose-tools.yml run --rm php_quality_tools phpmd ./docroot/modules/custom,./docroot/themes/custom,./docroot/profiles/custom text phpmd.rules.xml

phpcpd: ## Run PHP Copy Paste Detector.
	$(DOCKER_COMPOSE) -f docker-compose-tools.yml run --rm php_quality_tools phpcpd ./docroot/modules/custom ./docroot/themes/custom ./docroot/profiles/custom

phpcbf: ## Run PHP Code Beautifier and Fixer.
	$(DOCKER_COMPOSE) -f docker-compose-tools.yml run --rm php_quality_tools phpcbf ./docroot/modules/custom ./docroot/themes/custom ./docroot/profiles/custom

security_check: ## Search for vulnerabilities into composer.lock.
	$(DOCKER_COMPOSE) -f docker-compose-tools.yml run --rm php_security_checker security:check --dir=/code

phpunit: ## Run PHPUnit (e.g: make phpunit module="module_path")
	$(DOCKER_COMPOSE) exec php ./vendor/bin/phpunit $(module)

.PHONY: phpcs phpstan phpmd phpcpd security_check phpunit

.DEFAULT_GOAL := help
help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'
.PHONY: help
