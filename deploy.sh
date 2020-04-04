#!/bin/bash
#
# WARNING: do not use this script on production environment
# this scipt should only be used to setup a test environment
#
# this script setup a sharded cluster on a local machine. 
# To run this script, use the command: 
#
#   ./deploy.sh path/to/config.txt /path/to/db/folder
#
# make sure that mongod, mongos and mongo are linked correctly 
# you can achieved this using the following command: 
# sudo ln -s /path/to/mongo/bin/mongo /bin/mongo

# text colors
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)


if [ -z "$1" ]
  then
    echo "${red}No configuration file provided${reset}"
    exit 1
fi

if [ -z "$2" ]
  then
    echo "${red}No db folder specified${reset}"
    exit 1
fi

config=$1
dbfolder=$2

echo "" > conf_svr.log
echo "" > mongos.log
echo "" > shard.log


# clear directory
rm -r "$dbfolder"/config0 "$dbfolder"/config1 "$dbfolder"/config2 "$dbfolder"/shard0 "$dbfolder"/shard1

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
done < <(sed '/^[[:space:]]*\(#.*\)\?$/d' "$config")


#start config servers
for index in "${!CONFIG_HOSTS[@]}"
do
    mkdir "$dbfolder"/config"$index"
    echo "starting config server $index"
	mongod --configsvr --port "${CONFIG_PORTS[index]}" --dbpath "$dbfolder"/config"$index" --replSet conf --logpath conf_svr.log --fork
	sleep 1
done

sleep 10

echo "${green}config servers deployed${reset}"


mongo --host "${CONFIG_HOSTS[0]}" --port "${CONFIG_PORTS[0]}" --eval "rs.initiate( { _id: \"conf\", members: [ {_id: 0, host:\"${CONFIG_URL[0]}\"}, {_id: 1, host:\"${CONFIG_URL[1]}\"}, {_id: 2, host:\"${CONFIG_URL[2]}\"} ]})"&

# sleep so a primary shard can be designed among config servers
sleep 15

mongos --port "${MONGOS_PORT[0]}" --configdb "conf/${CONFIG_URL[0]},${CONFIG_URL[1]},${CONFIG_URL[2]}" --logpath mongos.log --fork

echo "${green}mongos instance configured${reset}"

sleep 5

for index in "${!SHARD_HOSTS[@]}"
do
    mkdir "$dbfolder"/shard"$index"
    echo "starting shard $index"
	mongod --shardsvr --port "${SHARD_PORTS[index]}" --dbpath "$dbfolder"/shard"$index"  --logpath shard.log --fork
    sleep 5
    mongo --host "${MONGOS_HOST[0]}" --port "${MONGOS_PORT[0]}" --eval "sh.addShard(\"${SHARD_HOSTS[$index]}:${SHARD_PORTS[$index]}\");"&
	sleep 5
	echo "${green}shard  ${SHARD_HOSTS[$index]}:${SHARD_PORTS[$index]} added${reset}"
done

# make sure that the sharded cluster has been deployed correctly
mongo --host "${MONGOS_HOST[0]}" --port "${MONGOS_PORT[0]}" --eval "sh.status();" > result.txt

