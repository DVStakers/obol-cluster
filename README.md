# Repository Archived

> :warning: **Warning:** This repository is no longer supported or maintained.
>
> Please use the [Obol repository](https://github.com/ObolNetwork/charon-distributed-validator-node) for ongoing support and updates.


# Obol Cluster

This repository contains the code to run any number of [Obol](https://obol.tech/) nodes on a single machine.

It uses Teku as the VC client as that is currently the only VC client that supports MEV Boost.

## Requirements

- Docker

## Getting Started

1. Create a `.env` file based on the `.env.sample` file provided.
2. In the `.env` file set the value of `ACTIVE_NODES` to the nodes you want to run. If you have been given a file called ` node5.tar.xz` then you would set `ACTIVE_NODES` to `5`.
3. For each node you want to run, the variable `CHARON_?_P2P_TCP_ADDRESS_PORT` must be set, where `?` is set to the node number. For example, if you want to run node `5`, then `CHARON_5_P2P_TCP_ADDRESS_PORT` must be set to the port you want to use for node `5`.
4. When the `.env` file is ready run `./generate-docker-compose.sh` and confirm the nodes you want to run.
5. Create the directory structure `.charon/cluster/node?/` and untar the `node?.tar.xz` files into it where `?` should be set to the node number. The file structure should look like this:

```bash
├── <OTHER_FILES_IN_THIS_REPO>
├── .charon/
    ├── cluster/
        ├── node?/
            ├── charon-enr-private-key
            ├── cluster-lock.json
            ├── deposit-data.json
            ├── validator_keys/
```

6. Run `docker compose up -d` to start the nodes.

## Commands

### Generate the docker-compose file

```bash
./generate-docker-compose.sh
```

### Start the nodes

```bash
docker compose up -d
```

### View the logs

```bash
docker compose logs -f
```

### Stop the nodes

```bash
docker compose down
```

### View the Grafana dashboard

Use the IP address of the machine where this docker-compose is being started and the port that was set in the `.env` file for the `MONITORING_PORT_GRAFANA` variable.

```bash
http://<IP_ADDRESS>:<MONITORING_PORT_GRAFANA>
```

## Support

For any questions about this repo please contact @EridianAlpha on X or TG.
