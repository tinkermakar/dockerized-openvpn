# ENVIRONMENT VARIABLES
include .env
ifndef DOCKER_CONTAINER
$(error DOCKER_CONTAINER is not set)
endif
ifndef OPENVPN_SERVER_HOST
$(error OPENVPN_SERVER_HOST is not set)
endif
ifndef OPENVPN_SERVER_PORT
$(error OPENVPN_SERVER_PORT is not set)
endif
ifndef NEW_USER
$(error NEW_USER is not set)
endif

OVPN_FILE_NAME=$(NEW_USER).ovpn
# END ENVIRONMENT VARIABLES


help:
	@echo "All-in-one command:"
	@echo "  danger-all              - Run a sequence of commands to get it up and running from scratch or start over"
	@echo
	@echo "Main commands:"
	@echo "  create-user             - Create a new user in the OpenVPN Access Server"
	@echo "  configure               - Misc OpenVPN Server configurations"
	@echo "  download-config         - Download the OVPN configuration file for the new user and display it"
	@echo
	@echo "Utility commands:"
	@echo "  help                    - Display this help message"
	@echo "  logs                    - Follow the Docker container logs"
	@echo "  extract-admin-password  - Extract the admin password from logs"
	@echo "  restart-container       - Restart the Docker container"
		

extract-admin-password:
	@echo "Extracting password from logs..."
	@docker logs $(DOCKER_CONTAINER) 2>&1 | grep 'Auto-generated pass =' | tail -1 | grep -oP 'Auto-generated pass = "\K[^"]+'

logs:
	docker logs -f $(DOCKER_CONTAINER)

settings-get:
	docker exec $(DOCKER_CONTAINER) sacli ConfigQuery

danger-start-over:
	@echo "Purging Docker container $(DOCKER_CONTAINER)..."
	docker compose down -v
	docker compose up --build -d
	sleep 1m

create-user:
	@echo "Creating new user $(NEW_USER)..."
	@docker exec $(DOCKER_CONTAINER) sacli --user $(NEW_USER) --key "type" --value "user" UserPropPut
	@docker exec -it $(DOCKER_CONTAINER) sacli --user $(NEW_USER) --key "prop_autologin" --value "true" UserPropPut

configure:
	@echo "Pushing DNS settings..."
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.client.routing.reroute_dns" --value "custom" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.server.dhcp_option.dns.0" --value "8.8.8.8" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.server.dhcp_option.dns.1" --value "1.1.1.1" ConfigPut

	@echo "Adding redirect-gateway def1 to Additional OpenVPN Config Directives..."
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.client.config_text" --value "redirect-gateway def1" ConfigPut

	@echo "Agreeing to EULA..."
	@docker exec $(DOCKER_CONTAINER) sacli --key "aui.eula_version" --value "5" ConfigPut

	@echo "Setting Network Address to $(OPENVPN_SERVER_HOST)..."
	@docker exec $(DOCKER_CONTAINER) sacli --key "host.name" --value "$(OPENVPN_SERVER_HOST)" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.daemon.0.listen.port" --value "$(OPENVPN_SERVER_PORT)" ConfigPut

	@echo "Disabling TCP and enabling only UDP for client connections..."
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.server.daemon.tcp" --value "false" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.server.daemon.tcp.n_daemons" --value "0" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.daemon.0.listen.protocol" --value "udp" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.server.daemon.enable" --value "false" ConfigPut
	@docker exec $(DOCKER_CONTAINER) sacli --key "vpn.server.port_share.enable" --value "false" ConfigPut

	@echo "Updating server ciphers..."
	@docker exec -it $(DOCKER_CONTAINER) sacli --key "vpn.server.data_ciphers" --value "AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC" ConfigPut

restart-container:
	@echo "Restarting Docker container..."
	docker restart $(DOCKER_CONTAINER)
	sleep 5

download-config:
	@echo "Downloading OVPN configuration for user $(NEW_USER)..."
	@docker exec $(DOCKER_CONTAINER) sacli --user $(NEW_USER) GetAutologin > $(OVPN_FILE_NAME)
	@echo
	@echo
	@cat $(OVPN_FILE_NAME)
	@echo
	@echo

danger-all: danger-start-over create-user configure restart-container download-config
	@echo "All tasks completed successfully."
