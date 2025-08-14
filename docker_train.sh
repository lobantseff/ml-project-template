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
    echo "  Start a training Docker container to run ML model training."
    echo "  This script will start a container and execute the training script."
    echo ""
    echo -e "\033[1mPositional arguments:\033[0m"
    echo "  image_name                       Docker image name (if omitted, read from .env)"
    echo ""
    echo -e "\033[1mOptions:\033[0m"
    echo "  -c, --container-name <name>      Container name (default: <image_name>.train)"
    echo "  -w, --workspace <path>           Absolute path to the workspace folder (will be cached)"
    echo "  -d, --data-dir <path>            Absolute path to the read-only data directory (will be cached)"
    echo "  -g, --gpus <gpus>                GPUs visible in container [all]"
    echo "  -e, --experiment <name>          Experiment name (default: auto-generated timestamp)"
    echo "      --restart <Y|n>              Restart container on reboot [Y]"
    echo "      --docker-args <args>         Additional arguments to pass to docker run"
    echo "      --non-interactive            Run without prompts (use provided values or defaults)"
    echo "      --detached                   Run training in detached mode (background)"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo -e "\033[1mExamples:\033[0m"
    echo "  # Interactive training (default, will prompt for image name if not in .env)"
    echo "  $0"
    echo ""
    echo "  # Background training"
    echo "  $0 my-image:latest --detached"
    echo ""
    echo "  # Using all GPUs"
    echo "  $0 my-image:latest --gpus 'all'"
    echo ""
    echo "  # Using only GPUs 0 and 1"
    echo "  $0 my-image:latest --gpus '0,1'"
    echo ""
    echo "  # With experiment name"
    echo "  $0 my-image:latest --experiment \"feature_engineering_v2\""
    echo ""
    echo "  # With additional Docker arguments"
    echo "  $0 my-image:latest --docker-args '--privileged --network=host'"
    echo ""
    echo "  # Non-interactive with specific options"
    echo "  $0 my-image:latest -c mycontainer_train -w /home/user/ws --non-interactive --detached"
}

# Initialize variables
docker_image_name=""
container_name=""
ws=""
data_dir=""
gpus_prompt=""
rc=""
docker_extra_args=""
detached_mode=false
experiment_name=""

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

# Detect detached mode
for arg in "$@"; do
    if [[ "$arg" == "--detached" ]]; then
        detached_mode=true
        # Remove --detached from arguments
        set -- "${@/--detached/}"
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
        -e | --experiment)
            experiment_name="$2"
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
echo -e "${GREEN}                    Training Container Setup Tool                      ${NC}"
echo -e "${GREEN}========================================================================${NC}"
echo ""

if [[ "$non_interactive" == false ]]; then
    echo -e "${BLUE}This script will help you start a training container.${NC}"
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

# Generate experiment name and setup experiment directory
if [ -z "$experiment_name" ]; then
    # Generate timestamp-based experiment name: YYMMDD_HHMM
    timestamp=$(date +"%y%m%d_%H%M")
    if [ "$non_interactive" = false ]; then
        read -p "Experiment name [$timestamp-experiment]: " experiment_name_input
        experiment_name=${experiment_name_input:-"$timestamp-experiment"}
    else
        experiment_name="$timestamp-experiment"
    fi
else
    # Add timestamp prefix if not already present
    if [[ ! "$experiment_name" =~ ^[0-9]{6}_[0-9]{4}- ]]; then
        timestamp=$(date +"%y%m%d_%H%M")
        experiment_name="$timestamp-$experiment_name"
    fi
fi
echo -e "${GREEN}✓ Using experiment name: $experiment_name${NC}"

# Get container name
if [ -z "$container_name" ]; then
    container_name=$(get_env_var container_name)
    if [ -z "$container_name" ]; then
        container_name="$(echo $docker_image_name | tr : .).train.$experiment_name"
    else
        container_name="$(echo $container_name | tr : .).train.$experiment_name"
    fi
    if [ "$non_interactive" = false ]; then
        read -r -p "Container name [$container_name]: " container_name_input
        container_name=${container_name_input:-$container_name}
    fi
fi

# Check if a training container is already running
existing_container=$(docker ps --filter "name=$container_name" --format "{{.Names}}" | head -1)
if [ ! -z "$existing_container" ]; then
    echo -e "${YELLOW}Training container '$container_name' is already running.${NC}"
    if [ "$non_interactive" = false ]; then
        read -r -p "Stop and restart training? [Y/n]: " restart_input
        restart_input=${restart_input:-Y}
        if [ "$restart_input" = "Y" ]; then
            echo -e "${BLUE}Stopping existing training container...${NC}"
            docker stop "$container_name" >/dev/null 2>&1 || true
            docker rm "$container_name" >/dev/null 2>&1 || true
        else
            echo -e "${BLUE}Exiting. Use 'docker logs -f $container_name' to monitor the running training.${NC}"
            exit 0
        fi
    else
        echo -e "${RED}Training container is already running. Use --non-interactive with caution.${NC}"
        exit 1
    fi
fi

# Remove any stopped container with the same name
docker rm "$container_name" >/dev/null 2>&1 || true
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
    echo -e "${YELLOW}Workspace directory '$ws' does not exist. Creating it...${NC}"
    mkdir -p "$ws"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create workspace directory '$ws'.${NC}"
        read -r -p "Please provide an existing workspace directory: " ws
    else
        break
    fi
done

echo -e "${GREEN}✓ Using workspace directory: $ws${NC}"

# Setup experiment directory structure
experiment_dir="$ws/experiments/$experiment_name"
echo -e "${BLUE}Setting up experiment directory: $experiment_dir${NC}"
mkdir -p "$experiment_dir"/{checkpoints,plots,tb_logs,code_snapshot}

# Create experiment metadata files
echo -e "${BLUE}Creating experiment metadata files...${NC}"

# System info for reproducibility
cat > "$experiment_dir/system_info.txt" << EOF
Experiment: $experiment_name
Date: $(date)
Host: $(hostname)
OS: $(uname -a)
Docker Image: $docker_image_name
Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "Not a git repository")
EOF

# Add GPU info if available
if command -v nvidia-smi &>/dev/null; then
    echo "" >> "$experiment_dir/system_info.txt"
    echo "=== GPU Information ===" >> "$experiment_dir/system_info.txt"
    nvidia-smi >> "$experiment_dir/system_info.txt"
fi

echo -e "${GREEN}✓ Experiment directory structure created${NC}"

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
    echo -e "${YELLOW}Data directory '$data_dir' does not exist. Creating it...${NC}"
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

# # ----------------------- Prompt for restart policy (on reboot) -------------------------
# if [ -z "$rc" ]; then
#     rc=$(get_env_var restart_container)
#     rc=${rc:-Y}
#     if [ "$non_interactive" = false ]; then
#         while true; do
#             read -p "Restart container on reboot? [Y/n]: " rc_input
#             rc=${rc_input:-$rc}
#             if [ "$rc" == "Y" ] || [ "$rc" == "n" ]; then
#                 break
#             else
#                 echo "Provide Y or n"
#             fi
#         done
#     fi
# fi
# if [ "$rc" != "Y" ] && [ "$rc" != "n" ]; then
#     echo "Invalid value for --restart. Use 'Y' or 'n'."
#     exit 1
# fi
# echo -e "\033[36mUsing restart policy: $rc\033[0m"

# Include any extra docker arguments
if [ ! -z "$docker_extra_args" ]; then
    echo -e "${BLUE}Using extra docker args: $docker_extra_args${NC}"
fi

# Start the training container
echo ""
echo -e "${BLUE}=== Starting Training Container ===${NC}"
docker_run_options=()

# if [ "$rc" == "Y" ]; then
#     docker_run_options+=(--restart unless-stopped)
# elif [ "$rc" == "n" ]; then
#     docker_run_options+=(--rm)
# fi

docker_run_options+=(--gpus $gpus)

# Set run mode (detached or interactive)
if [ "$detached_mode" = true ]; then
    docker_run_options+=(-d)
    echo -e "${BLUE}Running training in detached mode...${NC}"
else
    docker_run_options+=(-it)
    echo -e "${BLUE}Running training in interactive mode...${NC}"
fi

# Freeze code and create experiment-specific container
echo -e "${BLUE}Freezing code for experiment reproducibility...${NC}"

# Create a temporary container to freeze the current code state
temp_container_name="temp_freeze_${experiment_name}_$(date +%s)"
echo -e "${BLUE}Creating temporary container to freeze code: $temp_container_name${NC}"

# Start temporary container
docker run -d --name "$temp_container_name" --entrypoint="" "$docker_image_name" sleep infinity

# Copy current code to the container (freeze the code state)
tar --exclude='./ws' --exclude='./data' -czf - . | docker exec -i "$temp_container_name" tar -xzf - -C /code/

# Also create a code snapshot in the experiment directory for reference (only src code)
echo -e "${BLUE}Creating code snapshot in experiment directory...${NC}"
# Only copy the src directory - that's what matters for reproducibility
if [ -d "${PWD}/src" ]; then
    rsync -av --exclude='*.egg-info' "${PWD}/src/" "$experiment_dir/code_snapshot/src/"
    echo -e "${GREEN}✓ Code snapshot saved to $experiment_dir/code_snapshot/src${NC}"
else
    echo -e "${YELLOW}⚠ No src directory found, skipping code snapshot${NC}"
fi

# Generate requirements.txt from the current environment
echo -e "${BLUE}Generating frozen requirements.txt...${NC}"
docker exec "$temp_container_name" pip freeze > "$experiment_dir/requirements.txt"
echo -e "${GREEN}✓ Requirements frozen to $experiment_dir/requirements.txt${NC}"

# Commit the container with frozen code as a new experiment image
frozen_image_name="${docker_image_name%%:*}:exp-$experiment_name"
echo -e "${BLUE}Creating frozen experiment image: $frozen_image_name${NC}"
docker commit --change='WORKDIR /code' "$temp_container_name" "$frozen_image_name"

# Clean up temporary container
docker stop "$temp_container_name" >/dev/null 2>&1 || true
docker rm "$temp_container_name" >/dev/null 2>&1 || true

echo -e "${GREEN}✓ Code frozen in image: $frozen_image_name${NC}"

# Set up container mounts (no code mount since it's frozen in the image)
docker_run_options+=(-v "$HOME/.ssh:/root/.ssh")
if [ "$SSH_AUTH_SOCK" ]; then
    docker_run_options+=(-v "$SSH_AUTH_SOCK:/ssh-agent")
    docker_run_options+=(-e "SSH_AUTH_SOCK=/ssh-agent")
fi
# Note: No code mount here - code is frozen in the image
if [ "$ws" ]; then
    docker_run_options+=(-v "$ws:/ws")
fi
if [ "$data_dir" ]; then
    docker_run_options+=(-v "$data_dir:/data:ro")
fi
# Pass experiment environment variables
docker_run_options+=(-e "EXPERIMENT_NAME=$experiment_name")
docker_run_options+=(-e "EXPERIMENT_DIR=/ws/experiments/$experiment_name")
docker_run_options+=(--name "$container_name")
docker_run_options+=(--shm-size 32G)
docker_run_options+=(--ulimit stack=67108864)
docker_run_options+=(--workdir /code)

# Include any extra docker arguments
if [ ! -z "$docker_extra_args" ]; then
    docker_run_options+=($docker_extra_args)
fi

# Validate required arguments early if running non-interactively
if ! [ -t 0 ] && [ -z "$docker_image_name" ]; then
    echo -e "${RED}Error: Docker image name is required in non-interactive mode.${NC}" >&2
    exit 1
fi

# Run the Docker container with the training command
echo -e "${BLUE}Starting training container '$container_name' from frozen image '$frozen_image_name'...${NC}"
docker run "${docker_run_options[@]}" "$frozen_image_name" python src/segformer_devicenet/main.py

if [ "$detached_mode" = true ]; then
    echo ""
    echo -e "${GREEN}========================================================================${NC}"
    echo -e "${GREEN}               Training Container Successfully Started!                 ${NC}"
    echo -e "${GREEN}========================================================================${NC}"
    echo ""
    echo -e "${BLUE}Container Details:${NC}"
    echo -e "• ${YELLOW}Container name:${NC} $container_name"
    echo -e "• ${YELLOW}Experiment:${NC} $experiment_name"
    echo -e "• ${YELLOW}Experiment dir:${NC} $experiment_dir"
    echo -e "• ${YELLOW}Base image:${NC} $docker_image_name"
    echo -e "• ${YELLOW}Frozen image:${NC} $frozen_image_name"
    echo -e "• ${YELLOW}Training command:${NC} python src/segformer_devicenet/main.py"
    echo -e "• ${YELLOW}Code:${NC} frozen in container (reproducible)"
    echo -e "• ${YELLOW}Workspace:${NC} $ws → /ws"
    echo -e "• ${YELLOW}Data:${NC} $data_dir → /data (read-only)"
    echo -e "• ${YELLOW}Attached GPUs:${NC} $gpus"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "• ${YELLOW}Monitor training logs:${NC} docker logs -f $container_name"
    echo -e "• ${YELLOW}Attach to container:${NC} docker exec -it $container_name bash"
    echo -e "• ${YELLOW}Stop training:${NC} docker stop $container_name"
    echo -e "• ${YELLOW}Remove container:${NC} docker rm $container_name"
    echo ""
    echo -e "${BLUE}Training artifacts will be saved to: ${GREEN}$ws${NC}"
    echo -e "${BLUE}This information is saved in the .train_hint file.${NC}"
    
    # Write plain version to .train_hint file
    hint_content="Training Container Successfully Started!
    
    Container Details:
    • Container name: $container_name
    • Experiment: $experiment_name
    • Base image: $docker_image_name
    • Frozen image: $frozen_image_name
    • Training command: python src/segformer_devicenet/main.py
    • Code: frozen in container (reproducible)
    • Workspace: $ws → /ws
    • Data: $data_dir → /data (read-only)
    • Attached GPUs: $gpus
    
    Experiment Artifacts:
    • Experiment directory: $experiment_dir
    • Training logs: $experiment_dir/training.log
    • Checkpoints: $experiment_dir/checkpoints/
    • Plots: $experiment_dir/plots/
    • TensorBoard logs: $experiment_dir/tb_logs/
    • System info: $experiment_dir/system_info.txt
    • Frozen requirements: $experiment_dir/requirements.txt
    • Config: $experiment_dir/config.json
    
    Next steps:
    • Monitor training logs: docker logs -f $container_name
    • Attach to container: docker exec -it $container_name bash
    • Stop training: docker stop $container_name
    • Remove container: docker rm $container_name
    
    Training artifacts will be saved to: $experiment_dir"
    
    echo "$hint_content" > .train_hint
else
    echo ""
    echo -e "${GREEN}Training completed. Check the experiment directory (${YELLOW}$experiment_dir${NC})${GREEN} for training artifacts.${NC}"
fi
