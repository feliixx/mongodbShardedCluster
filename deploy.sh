#!/bin/bash
#
# WARNING: do not use this script on production environment
# this scipt should only be used to setup a test environment
#
# this script setup a sharded cluster on a local machine.
# To run this script, use the command:
#
#   ./deploy.sh /path/to/db/folder nb_shard
#
# make sure that mongod, mongos and mongo are linked correctly
# you can achieved this using the following command:
# sudo ln -s /path/to/mongo/bin/mongo /bin/mongo

# text colors
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

if [ -z "$1" ]; then
  echo "${red}No db folder specified${reset}"
  exit 1
fi

if [ -z "$2" ]; then
  echo "${red}Number of shard is missing${reset}"
  exit 1
fi

dbfolder=$1
nb_shard=$2

cleanup() {
  rm -r "$dbfolder"/logs "$dbfolder"/config0 "$dbfolder"/config1 "$dbfolder"/config2
  rm -r "$dbfolder"/shard*
  mkdir "$dbfolder"/logs
}

start_config_server() {

  config_port=27018

  for i in $(seq 1 3)
  do 
    mkdir "$dbfolder"/config"$i"
    echo "starting config server $i"
    mongod --configsvr --port "$config_port" --dbpath "$dbfolder"/config"$i" --replSet conf --logpath "$dbfolder/logs/conf_svr_$i.log" --fork
    sleep 1
    ((config_port++))
  done

  sleep 10

  echo "${green}config servers deployed${reset}"

  mongo --port 27018 --eval "rs.initiate( { _id: \"conf\", members: [ {_id: 0, host:\"localhost:27018\"}, {_id: 1, host:\"localhost:27019\"}, {_id: 2, host:\"localhost:27020\"} ]})" &

}

start_mongos() {

  mongos --port 27017 --configdb "conf/localhost:27018,localhost:27019,localhost:27020" --logpath "$dbfolder/logs/mongos.log" --fork

  echo "${green}mongos instance configured${reset}"
}

start_shards() {

  first_rs_port=27021
  second_rs_port=27022
  index=1

  for i in $(seq 1 "$nb_shard")
  do 

    echo "starting shard $i"

    mkdir "$dbfolder"/shard"$index"
    mongod --shardsvr --replSet "shardRs$i" --port "$first_rs_port" --dbpath "$dbfolder"/shard"$index" --logpath "$dbfolder/logs/shard_$index.log" --fork
    sleep 1

    ((index+=1))

    mkdir "$dbfolder"/shard"$index"
    mongod --shardsvr --replSet "shardRs$i" --port "$second_rs_port" --dbpath "$dbfolder"/shard"$index" --logpath "$dbfolder/logs/shard_$index.log" --fork
    sleep 1

    ((index+=1))

    mongo --port "$second_rs_port" --eval "rs.initiate( { _id: \"shardRs$i\", members: [ {_id: 0, host:\"localhost:$first_rs_port\"}, {_id: 1, host:\"localhost:$second_rs_port\"} ]})" &
    sleep 5
  
    mongo --eval "sh.addShard(\"shardRs$i/localhost:$first_rs_port\");" &
    echo "${green}shard  $i added${reset}"

    ((first_rs_port+=2))
    ((second_rs_port+=2))

  done

}

cleanup

start_config_server
sleep 15

start_mongos
sleep 5

start_shards
sleep 15 

# make sure that the sharded cluster has been deployed correctly
mongo --eval "sh.status();" >result.txt