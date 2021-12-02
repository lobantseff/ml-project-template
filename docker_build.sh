#!/bin/bash
echo "Hi, let's set up your project."

curdir=${PWD##*/}
read -r -p "Set up Docker image name[:tag] [$curdir]: " docker_image_name
docker_image_name=${docker_image_name:-$curdir}

read -s -p "Set up password for Jupyter: " password
echo ""

echo $password > .jupyter_password
echo $docker_image_name > .docker_image_name

docker build -t $docker_image_name \
    --build-arg username=$(whoami) \
    --build-arg groupname=$(id -g -n) \
    --build-arg uid=$(id -u) \
    --build-arg gid=$(id -g) \
    .

# Install the packages in ./src
docker run -v ${PWD}:/code --name tmp_container $docker_image_name pip install -e .
docker commit --change='CMD jupyter lab --no-browser' tmp_container $docker_image_name
docker rm tmp_container
