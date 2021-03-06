#!/bin/bash

# include functions to create crypto material through fabric-ca
. scripts/registerEnroll.sh

# Turn off the containers and clean everything
if [ "$1" == "down" ]; then
  docker-compose -f docker-compose-cli.yaml -f docker-compose-etcdraft2.yaml down -f docker-compose-ca.yaml --volumes --remove-orphans
  docker-compose -f docker-compose-org6.yaml -f docker-compose-ca-org6.yaml -f docker-compose-orderer6.yaml down --volumes --remove-orphans
  docker rm $(docker ps -aq)
  docker volume prune -f
  rm -rf channel-artifacts
  rm -rf crypto-config
  rm -rf global.example.com
  rm -rf openssl_stuff
  exit 0
fi

# Generate the cryptographic material based on the configuration in crypto-config.yaml
#../bin/cryptogen generate --config=./crypto-config.yaml

# Create dockers for CAs and fix permissions
cur_uid=$(id -u)
cur_gid=$(id -g)
mkdir -p crypto-config/fabric-ca/
docker-compose -f docker-compose-ca.yaml up -d
sleep 10
docker exec ca_org1 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_org2 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_org3 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_org4 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_org5 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_orderer_org1 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_orderer_org2 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_orderer_org3 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_orderer_org4 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"
docker exec ca_orderer_org5 sh -c "chown -R $cur_uid:$cur_gid /etc/hyperledger/fabric-ca-server"

# Create the crypto material for the 5 organizations
createOrg 1 7054
createOrg 2 8054
createOrg 3 9054
createOrg 4 10054
createOrg 5 11054
createOrderer 1 7055
createOrderer 2 8055
createOrderer 3 9055
createOrderer 4 10055
createOrderer 5 11055

../bin/cryptogen generate --output="crypto-config" --config=./crypto-config2.yaml
cp -R crypto-config/peerOrganizations/global.example.com .
mkdir openssl_stuff

cd ../bin
# first phase of key shares generation
./alice dkg --config dkg/id-10001-input.yaml &
./alice dkg --config dkg/id-10002-input.yaml &
./alice dkg --config dkg/id-10003-input.yaml &
./alice dkg --config dkg/id-10004-input.yaml &
./alice dkg --config dkg/id-10005-input.yaml
# generate files for signer
cat dkg/id-10001-input.yaml | sed '2,3d' | sed '5,6d' > dkg/preamb1
cat dkg/id-10002-input.yaml | sed '2,3d' | sed '5,6d' > dkg/preamb2
cat dkg/id-10003-input.yaml | sed '2,3d' | sed '5,6d' > dkg/preamb3
cat dkg/id-10004-input.yaml | sed '2,3d' | sed '5,6d' > dkg/preamb4
cat dkg/id-10005-input.yaml | sed '2,3d' | sed '5,6d' > dkg/preamb5
cat dkg/id-10001-output.yaml | sed '15,$d' > dkg/post1
cat dkg/id-10002-output.yaml | sed '15,$d' > dkg/post2
cat dkg/id-10003-output.yaml | sed '15,$d' > dkg/post3
cat dkg/id-10004-output.yaml | sed '15,$d' > dkg/post4
cat dkg/id-10005-output.yaml | sed '15,$d' > dkg/post5
mkdir signer
cat dkg/preamb1 dkg/post1 > signer/id-10001-input_base.yaml
cat dkg/preamb2 dkg/post2 > signer/id-10002-input_base.yaml
cat dkg/preamb3 dkg/post3 > signer/id-10003-input_base.yaml
cat dkg/preamb4 dkg/post4 > signer/id-10004-input_base.yaml
cat dkg/preamb5 dkg/post5 > signer/id-10005-input_base.yaml
# extract public key
cat dkg/id-10001-output.yaml | sed -n '3,4p' | grep -o "[0-9]*" > dkg/pk
# generate root certificate
openssl req -new -key ../semproj_net/openssl_perm/privkey_root.pem \
-x509 -nodes -days 365 -out ../semproj_net/openssl_stuff/fakerootcert.pem \
-subj "/C=US/ST=North Carolina/L=San Francisco/O=global.example.com/CN=ca.global.example.com" \
#-config ../semproj_net/openssl_perm/openssl.conf
# generate message to be signed
python3 ./gen_cert.py ../semproj_net/openssl_stuff/fakerootcert.pem dkg/pk
# generate input file for signer
cat signer/id-10001-input_base.yaml signer/msg > signer/id-10001-input.yaml
cat signer/id-10002-input_base.yaml signer/msg > signer/id-10002-input.yaml
cat signer/id-10003-input_base.yaml signer/msg > signer/id-10003-input.yaml
cat signer/id-10004-input_base.yaml signer/msg > signer/id-10004-input.yaml
cat signer/id-10005-input_base.yaml signer/msg > signer/id-10005-input.yaml
# sign message
./alice signer --config signer/id-10001-input.yaml &
sleep 1
./alice signer --config signer/id-10002-input.yaml &
sleep 1
./alice signer --config signer/id-10003-input.yaml
# parse signature generated by alice
cat signer/id-10001-output.yaml | grep -o "[0-9]*" > signer/signature
# convert certificate from der to pem
openssl x509 -inform der -in ../semproj_net/openssl_stuff/fakerootcert.der -out ../semproj_net/openssl_stuff/fakerootcert_changedpk.pem
# replace signature in root certificate
python3 sign_cert.py ../semproj_net/openssl_stuff/fakerootcert_changedpk.pem ./signer/signature
# convert certificate from der to pem
openssl x509 -inform der -in ../semproj_net/openssl_stuff/new_cert.der -out ../semproj_net/openssl_stuff/ca.global.example.com-cert.pem
# move certificate into the right place
mkdir -p ../semproj_net/global.example.com/ca/
mkdir -p ../semproj_net/global.example.com/msp/cacerts/
mkdir -p ../semproj_net/global.example.com/users/Admin@global.example.com/msp/cacerts/
cp ../semproj_net/openssl_stuff/ca.global.example.com-cert.pem ../semproj_net/global.example.com/ca/
cp ../semproj_net/openssl_stuff/ca.global.example.com-cert.pem ../semproj_net/global.example.com/msp/cacerts/
cp ../semproj_net/openssl_stuff/ca.global.example.com-cert.pem ../semproj_net/global.example.com/users/Admin@global.example.com/msp/cacerts/

# resign admin certificate
mkdir -p ../semproj_net/global.example.com/users/Admin@global.example.com/msp/keystore
openssl ecparam -name secp256r1 -genkey -noout -out ../semproj_net/global.example.com/users/Admin@global.example.com/msp/keystore/priv_sk
openssl req -new -key ../semproj_net/global.example.com/users/Admin@global.example.com/msp/keystore/priv_sk -out ../semproj_net/openssl_stuff/fakeadmincert.csr -subj "/C=US/ST=North Carolina/L=San Francisco/OU=admin/CN=Admin@global.example.com"
openssl x509 -req -in ../semproj_net/openssl_stuff/fakeadmincert.csr -CA ../semproj_net/openssl_stuff/fakerootcert.pem -CAkey ../semproj_net/openssl_perm/privkey_root.pem -CAcreateserial -out ../semproj_net/openssl_stuff/fakeadmincert.pem -days 500 -sha256
python3 gen_cert.py ../semproj_net/openssl_stuff/fakeadmincert.pem
# generate input file for signer
cat signer/id-10001-input_base.yaml signer/msg > signer/id-10001-input.yaml
cat signer/id-10002-input_base.yaml signer/msg > signer/id-10002-input.yaml
cat signer/id-10003-input_base.yaml signer/msg > signer/id-10003-input.yaml
cat signer/id-10004-input_base.yaml signer/msg > signer/id-10004-input.yaml
cat signer/id-10005-input_base.yaml signer/msg > signer/id-10005-input.yaml
# sign message
./alice signer --config signer/id-10001-input.yaml &
sleep 1
./alice signer --config signer/id-10002-input.yaml &
sleep 1
./alice signer --config signer/id-10003-input.yaml
# parse signature generated by alice
cat signer/id-10001-output.yaml | grep -o "[0-9]*" > signer/signature
# replace signature in root certificate
python3 sign_cert.py ../semproj_net/openssl_stuff/fakeadmincert.pem ./signer/signature
# convert certificate from der to pem
mkdir -p ../semproj_net/global.example.com/users/Admin@global.example.com/msp/signcerts
openssl x509 -inform der -in ../semproj_net/openssl_stuff/new_cert.der -out ../semproj_net/global.example.com/users/Admin@global.example.com/msp/signcerts/Admin@global.example.com-cert.pem

cd ../semproj_net

# add cryptographic material for global MSP
cp -R ./global.example.com ./crypto-config/peerOrganizations/
chmod -R 775 ./crypto-config/peerOrganizations/global.example.com

# add Anna
cd scripts
./addUser_th.sh Anna
sleep 1
cd ..

# Create orderer genesis block, the channel transaction artifact and define anchor peers on the channel based on the configuration in configtxgen.yaml
export FABRIC_CFG_PATH=$PWD
../bin/configtxgen -profile SampleMultiNodeEtcdRaft -channelID byfn-sys-channel -outputBlock ./channel-artifacts/genesis.block
export CHANNEL_NAME=mychannel
../bin/configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME

for i in {1..5}; do
  ../bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org${i}MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org${i}MSP
done

# Start the network
docker-compose -f docker-compose-cli.yaml -f docker-compose-etcdraft2.yaml up -d

# Time to allow docker-compose to setup everything
sleep 15

# Scripts to complete network setup including chaincode installation and initialization
docker exec cli scripts/script.sh
docker exec cli scripts/appdef.sh
docker exec cli scripts/init_cc.sh
