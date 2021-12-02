Write-Output "Hi, let's set up your project."

$curdir = Split-Path -Path $PSScriptRoot -Leaf
$docker_image_name = Read-Host "Set up docker image name[:tag] [$($curdir)]"
$docker_image_name = ($curdir, $docker_image_name)[[bool]$docker_image_name]

$pwd_string = Read-Host "Set up password for Jupyter"

Write-Output $docker_image_name | Out-File ".docker_image_name" -Encoding ASCII
Write-Output $pwd_string | Out-File ".jupyter_password" -Encoding ASCII
Write-Output "" | Out-File ".ws_path" -Encoding ASCII

docker build -t $docker_image_name .

# Install the packages in ./src
docker run -v ${PWD}:/code --name tmp_container $docker_image_name pip install -e .
docker commit --change='CMD jupyter lab --no-browser' tmp_container $docker_image_name
docker rm tmp_container