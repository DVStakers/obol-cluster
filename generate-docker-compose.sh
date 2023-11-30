#!/bin/bash

source .env

# Check with the user
echo "These are the ACTIVE_NODES specified in the .env file: $ACTIVE_NODES"
echo -n "Are they correct? (y/n): "
read user_input

if [[ $user_input != 'y' ]]; then
  echo "Edit the .env file to change the ACTIVE_NODES"
  exit 1
fi

DOCKER_COMPOSE_FILE="docker-compose.yml"
PROMETHEUS_CONFIG_FILE="monitoring/prometheus/prometheus.yml"

generate_node_service() {
  local NODE_NUMBER=$1
  cat <<-EOF
  node-${NODE_NUMBER}:
    <<: *node-template
    environment:
      <<: *node-env
      CHARON_PRIVATE_KEY_FILE: /opt/charon/.charon/cluster/node${NODE_NUMBER}/charon-enr-private-key
      CHARON_LOCK_FILE: /opt/charon/.charon/cluster/node${NODE_NUMBER}/cluster-lock.json
      CHARON_JAEGER_SERVICE: node-${NODE_NUMBER}
      CHARON_P2P_EXTERNAL_HOSTNAME: node-${NODE_NUMBER}
      CHARON_P2P_TCP_ADDRESS: 0.0.0.0:\${CHARON_${NODE_NUMBER}_P2P_TCP_ADDRESS_PORT}
      CHARON_BUILDER_API: ${BUILDER_API_ENABLED:-false}
    ports:
      - \${CHARON_${NODE_NUMBER}_P2P_TCP_ADDRESS_PORT}:\${CHARON_${NODE_NUMBER}_P2P_TCP_ADDRESS_PORT}/tcp

  vc-${NODE_NUMBER}:
    image: consensys/teku:\${TEKU_VERSION:-23.10.0}
    networks: [cluster]
    restart: unless-stopped
    command: |
      validator-client
      --data-base-path="/opt/data"
      --beacon-node-api-endpoint="http://node-${NODE_NUMBER}:3600"
      --metrics-enabled=true
      --metrics-host-allowlist="*"
      --metrics-interface="0.0.0.0"
      --metrics-port="8008"
      --validators-keystore-locking-enabled=false
      --network="\${NETWORK}"
      --validator-keys="/opt/charon/validator_keys:/opt/charon/validator_keys"
      --validators-graffiti="\${GRAFFITI}"
      --validators-proposer-blinded-blocks-enabled=${BUILDER_API_ENABLED:-false}
      --validators-proposer-config="http://node-${NODE_NUMBER}:3600/teku_proposer_config"
    depends_on: [node-${NODE_NUMBER}]
    volumes:
      - ./vc-clients/teku:/opt/data
      - ./vc-clients/teku/run_validator.sh:/scripts/run_validator.sh
      - .charon/cluster/node${NODE_NUMBER}/validator_keys:/opt/charon/validator_keys
EOF
}

generate_prometheus_config() {
  local NODE_NUMBER=$1
  cat <<-EOF
  - job_name: "node-${NODE_NUMBER}"
    static_configs:
      - targets: ["node-${NODE_NUMBER}:3620"]
  - job_name: "vc-${NODE_NUMBER}"
    static_configs:
      - targets: ["vc-${NODE_NUMBER}:8008"]
EOF
}

cat <<-'EOF' > $DOCKER_COMPOSE_FILE
version: "3.8"

x-node-base: &node-base
  image: obolnetwork/charon:${CHARON_VERSION:-v0.18.0}
  restart: unless-stopped
  networks: [cluster]
  depends_on: [relay]
  volumes:
    - ./.charon:/opt/charon/.charon/

x-node-env: &node-env
  CHARON_BEACON_NODE_ENDPOINTS: ${CHARON_BEACON_NODE_ENDPOINTS}
  CHARON_LOG_LEVEL: ${CHARON_LOG_LEVEL:-info}
  CHARON_LOG_FORMAT: ${CHARON_LOG_FORMAT:-console}
  CHARON_VALIDATOR_API_ADDRESS: 0.0.0.0:3600
  CHARON_MONITORING_ADDRESS: 0.0.0.0:3620
  CHARON_JAEGER_ADDRESS: 0.0.0.0:6831

x-node-template: &node-template
  <<: *node-base
  environment:
    <<: *node-env
    CHARON_P2P_RELAYS: ${CHARON_P2P_RELAYS}

services:
  relay:
    <<: *node-base
    command: relay
    depends_on: []
    environment:
      <<: *node-env
      CHARON_HTTP_ADDRESS: 0.0.0.0:${CHARON_RELAY_PORT}
      CHARON_DATA_DIR: /opt/charon/relay
      CHARON_P2P_EXTERNAL_HOSTNAME: ${CHARON_P2P_EXTERNAL_HOSTNAME}
      CHARON_P2P_TCP_ADDRESS: 0.0.0.0:${CHARON_RELAY_P2P_TCP_ADDRESS_PORT}
    volumes:
      - ./relay:/opt/charon/relay:rw
    ports:
      - ${CHARON_RELAY_P2P_TCP_ADDRESS_PORT}:${CHARON_RELAY_P2P_TCP_ADDRESS_PORT}/tcp
      - ${CHARON_RELAY_PORT}:${CHARON_RELAY_PORT}/tcp
EOF


IFS=',' read -ra NODES <<< "$ACTIVE_NODES"
for NODE_NUMBER in "${NODES[@]}"; do
  generate_node_service $NODE_NUMBER >> $DOCKER_COMPOSE_FILE
done

cat <<-'EOF' >> $DOCKER_COMPOSE_FILE
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION:-v2.44.0}
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    networks: [cluster]
    restart: unless-stopped

  grafana:
    image: grafana/grafana:${GRAFANA_VERSION:-9.5.3}
    depends_on: [prometheus]
    volumes:
      - ./monitoring/grafana/datasource.yml:/etc/grafana/provisioning/datasources/datasource.yml
      - ./monitoring/grafana/dashboards.yml:/etc/grafana/provisioning/dashboards/datasource.yml
      - ./monitoring/grafana/grafana.ini:/etc/grafana/grafana.ini:ro
      - ./monitoring/grafana/dashboards:/etc/dashboards
    networks: [cluster]
    restart: unless-stopped
    ports:
      - "${MONITORING_PORT_GRAFANA}:3000"

  node-exporter:
    image: prom/node-exporter:${NODE_EXPORTER_VERSION:-v1.6.0}
    networks: [cluster]
    restart: unless-stopped

  jaeger:
    image: jaegertracing/all-in-one:${JAEGAR_VERSION:-1.46.0}
    networks: [cluster]
    restart: unless-stopped

networks:
  cluster:
EOF

# Write the beginning part of the Prometheus config file
cat <<-'EOF' > $PROMETHEUS_CONFIG_FILE
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
EOF

# Generate the dynamic Prometheus config
for NODE_NUMBER in "${NODES[@]}"; do
  generate_prometheus_config $NODE_NUMBER >> $PROMETHEUS_CONFIG_FILE
done

# Write the remaining static part of the Prometheus config file
cat <<-'EOF' >> $PROMETHEUS_CONFIG_FILE
  - job_name: "node-exporter"
    static_configs:
      - targets: ["node-exporter:9100"]
EOF

# Check if PROMETHEUS_CREDENTIALS and PROMETHEUS_REMOTE_WRITE_URL are set and then append the remote_write section
if [[ -n $PROMETHEUS_CREDENTIALS && -n $PROMETHEUS_REMOTE_WRITE_URL ]]; then
  cat <<-EOF >> $PROMETHEUS_CONFIG_FILE
remote_write:
  - url: $PROMETHEUS_REMOTE_WRITE_URL
    authorization:
      credentials: $PROMETHEUS_CREDENTIALS
EOF
fi

echo "Success! The docker-compose.yml and monitoring/prometheus/prometheus.yml files have been generated."
