#!/bin/bash

docker build -t docker.io/sholly/vault-initadapter . 
docker tag docker.io/sholly/vault-initadapter:latest docker.io/sholly/vault-initadapter:0.0.1
docker push docker.io/sholly/vault-initadapter:0.0.1
