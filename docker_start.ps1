param([String]$ws="")

# Read default image name from build output
$docker_image_name = Get-Content ".docker_image_name"

# Prompt for workspace folder
$ws = Read-Host "Absolute path to project workspace folder [$ws_dump]"
$ws = ($ws_dump, $ws)[[bool]$ws]
if ($ws) 
{
    Write-Output $ws | Out-File ".ws_path" -Encoding ASCII
}

# Prompt for custom container name
$container_name = Read-Host "Container name [$($docker_image_name)]"
$container_name = ($docker_image_name, $container_name)[[bool]$container_name]

# Prompt for GPUS visible in container
$gpus_prompt = Read-Host "GPUs [all]"
$gpus_prompt = ("all", $gpus_prompt)[[bool]$gpus_prompt]
$gpus = '"device=str"'.replace('str',$gpus_prompt)

# Prompt for host Jupyter port
$jupyter_port = Read-Host "Jupyter port [8888]"
$jupyter_port = (8888, $jupyter_port)[[bool]$jupyter_port]

docker run --rm --gpus ${gpus} -d -v ${PWD}:/code -v ${ws}:/ws -p ${jupyter_port}:8888 --name $container_name $docker_image_name

echo ""
echo "- Jupyter Lab is now available at: localhost:$jupyter_port/lab" 
echo "- Jupyter Notebook is available at: localhost:$jupyter_port/tree"
echo "- To go inside the container use: docker exec -it $container_name bash"
echo "- To go inside the container and install packages use: docker exec -it --user=root $container_name bash"
if ($ws) 
{
    echo "- Inside the container $ws will be available at /ws" 
}
