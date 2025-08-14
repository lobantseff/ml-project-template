#!/bin/bash
set -e

# Colors for output
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# Function to display help message
show_help() {
    echo -e "\033[1mUsage:\033[0m $0 [image_name] [OPTIONS]"
    echo ""
    echo -e "\033[1mDescription:\033[0m"
    echo "  Start a development Docker container for interactive work."
    echo "  This script will start a container with mounted code, workspace, and data directories."
    echo ""
    echo -e "\033[1mPositional arguments:\033[0m"
    echo "  image_name                       Docker image name (optional, will prompt if not provided or read from .env)"
    echo ""
    echo -e "\033[1mOptions:\033[0m"
    echo "  -c, --container-name <name>      Container name (default: <image_name>.dev)"
    echo "  -w, --workspace <path>           Absolute path to the workspace folder (will be cached)"
    echo "  -d, --data-dir <path>            Absolute path to the read-only data directory (will be cached)"
    echo "  -g, --gpus <gpus>                GPUs visible in container [all]"
    echo "      --restart <Y|n>              Restart container on reboot [Y]"
    echo "      --docker-args <args>         Additional arguments to pass to docker run"
    echo "      --non-interactive            Run without prompts (use provided values or defaults)"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo -e "\033[1mExamples:\033[0m"
    echo "  # Interactive mode (default, will prompt for image name if not in .env)"
    echo "  $0"
    echo ""
    echo "  # With specific image"
    echo "  $0 my-image:latest"
    echo ""
    echo "  # Non-interactive with specific options"
    echo "  $0 my-image:latest -c mycontainer -w /home/user/ws -d /home/user/data --non-interactive"
    echo ""
    echo "  # Using all GPUs"
    echo "  $0 my-image:latest --gpus 'all'"
    echo ""
    echo "  # Using only GPUs 0 and 1"
    echo "  $0 my-image:latest --gpus '0,1'"
    echo ""
    echo "  # With additional Docker arguments"
    echo "  $0 my-image:latest --docker-args '--privileged --network=host'"
    echo ""
    echo "  # Using defaults from .env"
    echo "  $0 --non-interactive"
}

# Initialize variables
docker_image_name=""
container_name=""
ws=""
data_dir=""
gpus_prompt=""
rc=""
docker_extra_args=""

# Detect non-interactive mode
non_interactive=false
for arg in "$@"; do
    if [[ "$arg" == "--non-interactive" ]]; then
        non_interactive=true
        # Remove --non-interactive from arguments
        set -- "${@/--non-interactive/}"
        break
    fi
done

# Remove empty arguments (caused by set -- above)
args=()
for arg in "$@"; do
    if [[ -n "$arg" ]]; then
        args+=("$arg")
    fi
done
set -- "${args[@]}"

# -------------------- Parse positional image_name argument --------------------
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    docker_image_name="$1"
    shift
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c | --container-name)
            container_name="$2"
        shift; shift ;;
        -w | --workspace)
            ws="$2"
        shift; shift ;;
        -d | --data-dir)
            data_dir="$2"
        shift; shift ;;
        -g | --gpus)
            gpus_prompt="$2"
        shift; shift ;;
        --restart)
            rc="$2"
        shift; shift ;;
        --docker-args)
            docker_extra_args="$2"
        shift; shift ;;
        -h | --help)
            show_help
        exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information."
        exit 1 ;;
    esac
done

echo -e "${GREEN}========================================================================${NC}"
echo -e "${GREEN}                 Development Container Setup Tool                      ${NC}"
echo -e "${GREEN}========================================================================${NC}"
echo ""

if [[ "$non_interactive" == false ]]; then
    echo -e "${BLUE}This script will help you start a development container.${NC}"
    echo ""
fi

# Helper to read value from .env
get_env_var() {
    local var="$1"
    if [ -f .env ]; then
        grep -E "^${var}=" .env | head -n1 | cut -d'=' -f2-
    fi
}

# Get default image name from .env or prompt user
if [ -z "$docker_image_name" ]; then
    docker_image_name=$(get_env_var docker_image_name)
    if [ -z "$docker_image_name" ]; then
        docker_image_name="DOCKER_IMAGE_NAME"
        echo -e "${YELLOW}No image name provided and .env not found. Using placeholder: $docker_image_name${NC}"
    else
        echo -e "${BLUE}Using image name from .env: $docker_image_name${NC}"
    fi
    if [ "$non_interactive" = false ]; then
        read -r -p "Docker image name [$docker_image_name]: " docker_image_name_input
        docker_image_name=${docker_image_name_input:-$docker_image_name}
    fi
fi

# Check if the Docker image exists, prompt to retry if not
while ! docker image inspect "$docker_image_name" >/dev/null 2>&1; do
    if [ "$non_interactive" = true ]; then
        echo -e "${RED}Docker image '$docker_image_name' does not exist.${NC}"
        exit 1
    fi
    echo -e "${RED}Docker image '$docker_image_name' does not exist.${NC}"
    read -r -p "Docker image name [$docker_image_name]: " docker_image_name
done
echo -e "${GREEN}✓ Using image: $docker_image_name${NC}"

# Get container name
if [ -z "$container_name" ]; then
    container_name="$(echo $docker_image_name | tr : .).dev"
    if [ "$non_interactive" = false ]; then
        read -r -p "Container name [$container_name]: " container_name_input
        container_name=${container_name_input:-$container_name}
    fi
fi

# Check if the container with this name already exists, prompt to retry if it does
while docker ps -a --format '{{.Names}}' | grep -wq "$container_name"; do
    if [ "$non_interactive" = true ]; then
        echo -e "${RED}A container with the name '$container_name' already exists.${NC}"
        exit 1
    fi
    echo -e "${RED}A container with the name '$container_name' already exists.${NC}"
    read -r -p "Enter a different container name: " container_name
done
echo -e "${GREEN}✓ Using container name: $container_name${NC}"

# Get workspace folder
if [ -z "$ws" ]; then
    ws=$(get_env_var workspace_dir)
    ws_default="${PWD}/ws"
    if [ "$non_interactive" = false ]; then
        read -r -p "Workspace folder path [${ws:-$ws_default}]: " ws_input
        ws=${ws_input:-${ws:-$ws_default}}
    else
        ws=${ws:-$ws_default}
    fi
fi

# Check if the provided ws path exists, create if it doesn't
while [ ! -d "$ws" ]; do
    if [ "$non_interactive" = true ]; then
        echo -e "${BLUE}Creating workspace directory: $ws${NC}"
        mkdir -p "$ws"
        break
    fi
    echo -e "${YELLOW}Workspace directory '$ws' does not exist. Attempting to create it...${NC}"
    mkdir -p "$ws"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create workspace directory '$ws'.${NC}"
        read -r -p "Please provide an existing workspace directory: " ws
    else
        break
    fi
done

echo -e "${GREEN}✓ Using workspace directory: $ws${NC}"

# Get data directory
if [ -z "$data_dir" ]; then
    data_dir=$(get_env_var data_dir)
    data_dir_default="${PWD}/data"
    if [ "$non_interactive" = false ]; then
        read -r -p "Data directory path (read-only) [${data_dir:-$data_dir_default}]: " data_dir_input
        data_dir=${data_dir_input:-${data_dir:-$data_dir_default}}
    else
        data_dir=${data_dir:-$data_dir_default}
    fi
fi

# Check if the provided data_dir path exists, create if it doesn't
while [ ! -d "$data_dir" ]; do
    if [ "$non_interactive" = true ]; then
        echo -e "${BLUE}Creating data directory: $data_dir${NC}"
        mkdir -p "$data_dir"
        break
    fi
    echo -e "${YELLOW}Data directory '$data_dir' does not exist. Attempting to create it...${NC}"
    mkdir -p "$data_dir"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create data directory '$data_dir'.${NC}"
        read -r -p "Please provide an existing data directory: " data_dir
    else
        break
    fi
done

echo -e "${GREEN}✓ Using data directory: $data_dir${NC}"

# Get GPUs configuration
if [ -z "$gpus_prompt" ]; then
    gpus_env=$(get_env_var gpus)
    # Clean up the GPU specification for user display
    # Remove quotes and device= prefix if present in .env
    gpus_prompt=${gpus_env#\"device=}  # Remove "device= prefix
    gpus_prompt=${gpus_prompt%\"}      # Remove trailing quote
    gpus_prompt=${gpus_prompt#device=} # Remove device= prefix (if no quotes)
    if [ "$non_interactive" = false ]; then
        read -p "GPUs [${gpus_prompt:-all}]: " gpus_input
        gpus_prompt=${gpus_input:-${gpus_prompt:-all}}
    else
        gpus_prompt=${gpus_prompt:-all}
    fi
fi

# Construct the GPU argument for Docker
if [[ "$gpus_prompt" == "all" ]]; then
    gpus="all"
else
    # Always use device= prefix and quote the specification for Docker
    gpus="\"device=$gpus_prompt\""
fi
echo -e "${GREEN}✓ Using GPUs: $gpus_prompt${NC}"

# Show GPU memory usage if nvidia-smi is available and GPUs are present
if command -v nvidia-smi &>/dev/null; then
    echo -e "${BLUE}Current GPU memory usage:${NC}"
    nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits \
    | awk -F, '{printf "GPU %s (%s): Used %s MiB / %s MiB (Free: %s MiB)\n", $1, $2, $4, $3, $5}'
fi

# Get restart policy
if [ -z "$rc" ]; then
    rc=$(get_env_var restart_container)
    rc=${rc:-Y}
    if [ "$non_interactive" = false ]; then
        while true; do
            read -p "Restart container on reboot? [Y/n]: " rc_input
            rc=${rc_input:-$rc}
            if [ "$rc" == "Y" ] || [ "$rc" == "n" ]; then
                break
            else
                echo -e "${RED}Please enter Y or n${NC}"
            fi
        done
    fi
fi
if [ "$rc" != "Y" ] && [ "$rc" != "n" ]; then
    echo -e "${RED}Invalid value for --restart. Use 'Y' or 'n'.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Using restart policy: $rc${NC}"

# Include any extra docker arguments
if [ ! -z "$docker_extra_args" ]; then
    echo -e "${BLUE}Using extra docker args: $docker_extra_args${NC}"
fi

# Save configuration to .env file
echo ""
echo -e "${BLUE}=== Saving Configuration ===${NC}"
# Function to update or add a key-value pair in .env
update_env_var() {
    local key="$1"
    local value="$2"
    # Escape special characters in the value for sed
    local escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    if grep -q "^${key}=" .env 2>/dev/null; then
        # Key exists, update it using | as delimiter to avoid conflicts with special chars
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" .env
    else
        # Key doesn't exist, add it
        echo "${key}=${value}" >> .env
    fi
}

# Ensure .env exists
touch .env && chmod 600 .env

# Update each configuration value
update_env_var "docker_image_name" "$docker_image_name"
update_env_var "workspace_dir" "$ws"
update_env_var "data_dir" "$data_dir"
update_env_var "gpus" "$gpus"
update_env_var "restart_container" "$rc"

# Start the container
echo ""
echo -e "${BLUE}=== Starting Development Container ===${NC}"
docker_run_options=()

if [ "$rc" == "Y" ]; then
    docker_run_options+=(--restart unless-stopped)
    elif [ "$rc" == "n" ]; then
    docker_run_options+=(--rm)
fi

docker_run_options+=(--gpus $gpus)
docker_run_options+=(-d)
if [ "$HOME/.ssh" ]; then
    docker_run_options+=(-v "$HOME/.ssh:/root/.ssh")
fi
if [ "$SSH_AUTH_SOCK" ]; then
    docker_run_options+=(-v "$SSH_AUTH_SOCK:/ssh-agent")
    docker_run_options+=(-e "SSH_AUTH_SOCK=/ssh-agent")
fi
docker_run_options+=(-v "${PWD}:/code")
if [ "$ws" ]; then
    docker_run_options+=(-v "$ws:/ws")
fi
if [ "$data_dir" ]; then
    docker_run_options+=(-v "$data_dir:/data:ro")
fi
docker_run_options+=(--name "$container_name")
docker_run_options+=(--shm-size 32G)
docker_run_options+=(--ulimit stack=67108864)

# Include any extra docker arguments
if [ ! -z "$docker_extra_args" ]; then
    docker_run_options+=($docker_extra_args)
fi

# Validate required arguments early if running non-interactively
if ! [ -t 0 ] && [ -z "$docker_image_name" ]; then
    echo -e "${RED}Error: Docker image name is required in non-interactive mode.${NC}" >&2
    exit 1
fi

# Run the Docker container
echo -e "${BLUE}Starting container '$container_name' from image '$docker_image_name' with the command:${NC}"
echo -e "${YELLOW}>>> docker run ${docker_run_options[*]} $docker_image_name${NC}"
docker run "${docker_run_options[@]}" "$docker_image_name"

echo ""
echo -e "${GREEN}========================================================================${NC}"
echo -e "${GREEN}               Development Container Successfully Started!              ${NC}"
echo -e "${GREEN}========================================================================${NC}"
echo ""
echo -e "${BLUE}Container Details:${NC}"
echo -e "• ${YELLOW}Container name:${NC} $container_name"
echo -e "• ${YELLOW}Image:${NC} $docker_image_name"
echo -e "• ${YELLOW}Code:${NC} ${PWD} → /code"
echo -e "• ${YELLOW}Workspace:${NC} $ws → /ws"
echo -e "• ${YELLOW}Data:${NC} $data_dir → /data (read-only)"
echo -e "• ${YELLOW}Attached GPUs:${NC} $gpus"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "• ${YELLOW}Attach VSCode to container:${NC} ./docs/VSCODE.md"
echo -e "• ${YELLOW}Attach shell to container:${NC} docker exec -it $container_name bash"
echo -e "• ${YELLOW}Manage container's Python packages:${NC} ./pip_install.sh --help"
echo -e "• ${YELLOW}Stop container:${NC} docker stop $container_name"
echo -e "• ${YELLOW}Remove container:${NC} docker rm $container_name"
echo -e "• ${YELLOW}Update image:${NC} ./docker_update.sh"
echo ""
echo -e "${BLUE}This information is saved in the .hint file.${NC}"

# Write plain version to .hint file (strip color codes)
hint_content="Development Container Successfully Started!

Container Details:
• Container name: $container_name
• Image: $docker_image_name
• Code: ${PWD} → /code
• Workspace: $ws → /ws
• Data: $data_dir → /data (read-only)
• Attached GPUs: $gpus

Next steps:
• Attach VSCode to container: ./docs/VSCODE.md
• Attach shell to container: docker exec -it $container_name bash
• Manage container's Python packages: ./pip_install.sh --help
• Stop container: docker stop $container_name
• Remove container: docker rm $container_name
• Update image: ./docker_update.sh"

echo "$hint_content" > .hint
