#!/bin/bash

# Read default image name from build output
docker_image_name=$(cat .docker_image_name)

# Prompt for workspace folder
read -r -p "Absolute path to project workspace folder [$ws_dump]: " ws
ws=${ws:-$ws_dump}
if [ "$ws" ]
then
    echo $ws > .ws_path
fi

# Prompt for custom container name
read -r -p "Container name [$docker_image_name]: " container_name
container_name=${container_name:-$docker_image_name}

# Prompt for GPUS visible in container
read -p "GPUs [all]: " gpus_prompt
gpus_prompt=${gpus_prompt:-all}
gpus=\"'device=str'\"
gpus=$(sed "s/str/$gpus_prompt/g" <<< $gpus)

# Prompt for host Jupyter port
read -p "Jupyter port [8888]: " jupyter_port
jupyter_port=${jupyter_port:-8888}

docker run --rm --gpus $gpus -d -v ${PWD}:/code -v $ws:/ws -p $jupyter_port:8888 --user $(id -u):$(id -u) --name $container_name $docker_image_name

echo
echo - Jupyter Lab is now available at: localhost:$jupyter_port/lab  
echo - Jupyter Notebook is available at: localhost:$jupyter_port/tree
echo - To go inside the container use: docker exec -it $container_name bash
echo - To go inside the container and install packages use: docker exec -it --user=root $container_name bash
if [ "$ws" ]
then
      echo - Inside the container $ws will be available at /ws
fi

# OPTIONS DESCRIPTION
# --rm: remove container after stop
# --gpus all: allows access of docker container to your GPU
# -d: runs container in detached mode
# -v ${PWD}:/code: attaches current repository folder to /code in container. 
#                  All changes in the /code folder are changes in the repo folder.
# -v $1:/ws: attaches dir, which is specified in the first arg of docker_run.sh call
#            as /ws folder. All changes in the /ws folder are changes in the attached folder.
# -p 8888:8888: maps host port 8888 to 8888 port in teh container. The former is host port, 
#               the latter is the container port (8888 is default port for jupyter)
# --user $(id -u):$(id -u): run container under current user.
#                           By default container is run by root user, hence all files in 
#                           /code and /ws are created under the root user. Usually this is
#                           undesirable behaviour.
# --name container_name: give a name to the created container