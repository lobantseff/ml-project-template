param([String]$ws="")

# Read default image name from build output
$docker_image_name = Get-Content ".docker_image_name"

# Prompt for workspace folder
$ws = Read-Host "Absolute path to project workspace folder ['']"
$ws = ("", $ws)[[bool]$ws]

# Prompt for custom container name
$container_name = Read-Host "Container name [$($docker_image_name)]"
$container_name = ($docker_image_name, $container_name)[[bool]$container_name]

# Prompt for GPUS visible in container
$gpus_prompt = Read-Host "GPUs [all]"
$gpus_prompt = ("all", $gpus_prompt)[[bool]$gpus_prompt]
$gpus = '"device=str"'.replace('str',$gpus_prompt)

# Prompt for host Jupyter port
$jup_port = Read-Host "Jupyter port [8888]"
$jup_port = (8888, $jup_port)[[bool]$jup_port]

docker run --rm --gpus ${gpus} -d -v ${PWD}:/code -v ${ws}:/ws -p ${jup_port}:8888 --name $container_name $docker_image_name

echo ""
echo "- Jupyter Lab is now available at: localhost:$jup_port/lab" 
echo "- Jupyter Notebook is available at: localhost:$jup_port/tree"
echo "- To go inside the container use: docker exec -it $container_name bash"
if ($ws) 
{
    echo "- Inside the container $ws will be available at /ws" 
}
