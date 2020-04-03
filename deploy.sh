#!/bin/bash

# this script should be launched on the server where you want the 
# mongos to run. It should be run like this: 
# ./deploy.sh path/to/config.txt /path/to/db/folder

# make sure that mongod, mongos and mongo are linked correctly 
# you can achieved this using the following command: 
# sudo ln -s /path/to/mongo/bin/mongo /bin/mongo

echo "" > conf_svr.log
echo "" > mongos.log
echo "" > shard.log

# text colors
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# clear directory 
rm -r $2/config0 $2/config1 $2/config2 $2/shard0 $2/shard1

# read config file
declare -a CONFIG_HOSTS CONFIG_PORTS SHARD_HOSTS SHARD_PORTS CONFIG_URL
declare -A key_labels
key_labels["config"]="mongod config server"
key_labels["mongos"]="mongos instance" 
key_labels["shard"]="shard instance"

while IFS='=:' read -r key host port
do
    printf '%s: %s:%s\n' "${key_labels[$key]}" "$host" "$port"
    case "$key" in
    "config")
        CONFIG_HOSTS+=("$host")
        CONFIG_PORTS+=("$port")
        CONFIG_URL+=("$host:$port")
        ;;
    "mongos")
        MONGOS_HOST="$host"
        MONGOS_PORT="$port"
        ;;
    "shard")
        SHARD_HOSTS+=("$host")
        SHARD_PORTS+=("$port")
        ;;
    esac
done < <(sed '/^[[:space:]]*\(#.*\)\?$/d' $1)


#start config servers
for index in "${!CONFIG_HOSTS[@]}"
do
    mkdir $2/config$index
    echo "starting config server $index" 
	mongod --configsvr --port "${CONFIG_PORTS[index]}" --dbpath $2/config$index --replSet conf --logpath conf_svr.log --fork
	sleep 1
done

sleep 10
echo "${green}config servers deployed${reset}" 
# setup the config replica set. Only neccessary on first launch
mongo --host "${CONFIG_HOSTS[0]}" --port "${CONFIG_PORTS[0]}" --eval "rs.initiate( { _id: \"conf\", members: [ {_id: 0, host:\"${CONFIG_URL[0]}\"}, {_id: 1, host:\"${CONFIG_URL[1]}\"}, {_id: 2, host:\"${CONFIG_URL[2]}\"} ]})"&

# sleep so a primary shard can be designed among config servers
sleep 15
#start mongos 
mongos --port "${MONGOS_PORT[0]}" --configdb "conf/${CONFIG_URL[0]},${CONFIG_URL[1]},${CONFIG_URL[2]}" --logpath mongos.log --fork

echo "${green}mongos instance configured${reset}"

sleep 5
# start each shard and add them to the cluster
for index in "${!SHARD_HOSTS[@]}"
do
    mkdir $2/shard$index
    echo "starting shard $index"
	mongod --shardsvr --port "${SHARD_PORTS[index]}" --dbpath $2/shard$index  --logpath shard.log --fork
    sleep 5
    mongo --host "${MONGOS_HOST[0]}" --port "${MONGOS_PORT[0]}" --eval "sh.addShard(\"${SHARD_HOSTS[$index]}:${SHARD_PORTS[$index]}\");"&
	sleep 5
	echo "${green}shard  ${SHARD_HOSTS[$index]}:${SHARD_PORTS[$index]} added${reset}" 
done

# make sure that the sharded cluster has been deployed correctly 
mongo --host "${MONGOS_HOST[0]}" --port "${MONGOS_PORT[0]}" --eval "sh.status();" > result.txt

