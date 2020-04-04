# mongodbShardedCluster

deploy a mongodb sharded cluster on a local machine 

WARNING: do not use this in production environment. This script
is only intended for setting up a test environment

### Run 

Create a config file like this: 


```shell
# config server list, in folowing format: 
# config=<host>:<port>  
# started with --dbpath /data/configX where 
# X is the position of the server in the list 
config=localhost:27018
config=localhost:27019
config=localhost:27020

# mongos instance in folowing format:
# mongos=<host>:<port> 
mongos=localhost:27017

# shard list in folowing format: 
# shard=<host>:<port>
# started with --dbpath /data/shardX where 
# X is the position of the shard in the list
shard=localhost:27021
shard=localhost:27022
```

then run 

```shell
./deploy.sh config.txt /path/to/db/folder
```