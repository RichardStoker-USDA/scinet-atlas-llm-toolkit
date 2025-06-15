#!/bin/bash
#
# ollama_interactive.sh
# Version: 1.0
# Purpose: USDA-ARS SCINet Atlas LLM Interactive Session with GPU Support
# Created by: Richard Stoker (richard.stoker@usda.gov)
# GitHub: https://github.com/RichardStoker-USDA
# For: USDA-ARS HPC resource SCINet Atlas with NVIDIA GPU support via CUDA
#

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - adjust these as needed
DEFAULT_MODEL="gemma3:27b"
DEFAULT_CONTEXT_SIZE=131072  # 128k tokens
PROJECT_NAME="lemay_diet_guthealth"

# Initialize variables
MODEL_NAME=""
NUM_GPUS=""
CONTEXT_SIZE=""
AUTO_RUN=false
USER_SUBDIR=""

# Function to show usage
show_usage() {
    echo -e "${BLUE}==== USDA-ARS SCINet Atlas LLM Interactive Session ====${NC}"
    echo -e "${BLUE}Version 1.0 - Created by Richard Stoker for USDA-ARS HPC${NC}"
    echo -e "${GREEN}Contact: richard.stoker@usda.gov${NC}"
    echo -e "${GREEN}GitHub: https://github.com/RichardStoker-USDA${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "$0 [model_name] [num_gpus] [context_size] [flags]"
    echo ""
    echo -e "${YELLOW}Parameters:${NC}"
    echo "  model_name    - Ollama model name (default: $DEFAULT_MODEL)"
    echo "  num_gpus      - Number of GPUs to use (default: auto-detect)"
    echo "  context_size  - Context window size in tokens (default: $DEFAULT_CONTEXT_SIZE)"
    echo ""
    echo -e "${YELLOW}Optional Flags:${NC}"
    echo "  -s, --skip         Skip all confirmations (auto-run mode)"
    echo "  -u, --user-dir DIR Custom user subdirectory"
    echo "  -h, --help         Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  # Basic usage"
    echo "  $0 gemma3:27b 2 131072"
    echo ""
    echo -e "${YELLOW}  # Large context window"
    echo "  $0 llama3:70b 4 200000"
    echo ""
    echo -e "${YELLOW}  # Auto-run without confirmations"
    echo "  $0 deepseek-r1:8b 6 150000 -s"
    echo ""
    echo -e "${YELLOW}  # Custom user directory"
    echo "  $0 gemma3:27b 2 100000 -u custom_dir"
    echo ""
    echo -e "${YELLOW}Available Models (examples):${NC}"
    echo "• gemma3:27b (Google Gemma 3 - 27B parameters)"
    echo "• llama3:70b (Meta Llama 3 - 70B parameters)"
    echo "• deepseek-r1:8b (DeepSeek reasoning model - 8B parameters)"
    echo "• cogito:7b (Deep Cogito reasoning model - 7B parameters)"
    echo ""
    echo -e "${YELLOW}GPU Detection:${NC}"
    echo "• Script auto-detects available NVIDIA GPUs using nvidia-smi"
    echo "• Ensures proper load balancing across multiple A100 GPUs"
    echo "• Override detection by specifying num_gpus parameter"
    echo ""
    echo -e "${YELLOW}Interactive Features:${NC}"
    echo "• Direct CLI interaction with ollama"
    echo "• Configurable context window size"
    echo "• GPU-optimized model serving"
    echo "• Clean terminal environment"
}

# Parse command line arguments
parse_args() {
    # Set defaults
    MODEL_NAME="$DEFAULT_MODEL"
    NUM_GPUS="auto"
    CONTEXT_SIZE="$DEFAULT_CONTEXT_SIZE"
    
    # Parse positional arguments first
    if [ $# -ge 1 ] && [[ ! "$1" =~ ^- ]]; then
        MODEL_NAME="$1"
        shift
    fi
    
    if [ $# -ge 1 ] && [[ ! "$1" =~ ^- ]]; then
        NUM_GPUS="$1"
        shift
    fi
    
    if [ $# -ge 1 ] && [[ ! "$1" =~ ^- ]]; then
        CONTEXT_SIZE="$1"
        shift
    fi
    
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--skip)
                AUTO_RUN=true
                shift
                ;;
            -u|--user-dir)
                USER_SUBDIR="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
}

# GPU Detection Function
detect_gpus() {
    echo -e "\n${BLUE}Step 1: Detecting available NVIDIA GPUs...${NC}"
    
    # Check if nvidia-smi is available
    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${RED}Error: nvidia-smi not found. CUDA drivers may not be installed.${NC}"
        return 1
    fi
    
    # Get GPU count and info
    GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
    
    if [ $GPU_COUNT -eq 0 ]; then
        echo -e "${RED}Error: No NVIDIA GPUs detected${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Detected $GPU_COUNT NVIDIA GPU(s):${NC}"
    nvidia-smi --list-gpus | while IFS= read -r line; do
        echo -e "  ${BLUE}$line${NC}"
    done
    
    # Show memory info
    echo -e "\n${BLUE}GPU Memory Status:${NC}"
    nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits | \
    while IFS=, read -r index name total used free; do
        echo -e "  GPU $index ($name): ${GREEN}$free MB free${NC} / $total MB total"
    done
    
    # Auto-set GPU count if not specified
    if [ "$NUM_GPUS" = "auto" ]; then
        NUM_GPUS=$GPU_COUNT
        echo -e "\n${GREEN}Auto-detected GPU count: $NUM_GPUS${NC}"
    else
        if [ $NUM_GPUS -gt $GPU_COUNT ]; then
            echo -e "${YELLOW}Warning: Requested $NUM_GPUS GPUs, but only $GPU_COUNT available. Using $GPU_COUNT.${NC}"
            NUM_GPUS=$GPU_COUNT
        fi
        echo -e "\n${GREEN}Using $NUM_GPUS GPU(s) as specified${NC}"
    fi
    
    return 0
}

# Parse arguments
parse_args "$@"

echo -e "${BLUE}==== USDA-ARS SCINet Atlas LLM Interactive Session ====${NC}"
echo -e "${BLUE}Version 1.0 - Created by Richard Stoker for USDA-ARS HPC${NC}"
echo -e "${GREEN}Contact: richard.stoker@usda.gov${NC}"
echo -e "${GREEN}GitHub: https://github.com/RichardStoker-USDA${NC}"

echo -e "\n${BLUE}Configuration:${NC}"
echo -e "Model: ${GREEN}$MODEL_NAME${NC}"
echo -e "Context size: ${GREEN}$CONTEXT_SIZE tokens${NC}"
echo -e "Auto-run mode: ${GREEN}$AUTO_RUN${NC}"

# Auto-detect user directory
if [ -n "$USER_SUBDIR" ]; then
    USER_DIR="$USER_SUBDIR"
    echo -e "Using specified subdirectory: ${GREEN}$USER_DIR${NC}"
else
    CURRENT_DIR=$(pwd)
    if [[ "$CURRENT_DIR" == *"/90daydata/$PROJECT_NAME/"* ]]; then
        USER_DIR=$(echo "$CURRENT_DIR" | sed "s|.*/90daydata/$PROJECT_NAME/||" | cut -d'/' -f1)
        echo -e "Auto-detected user directory: ${GREEN}$USER_DIR${NC}"
    else
        USER_DIR="$(basename $HOME)_dev"
        echo -e "Using fallback directory: ${GREEN}$USER_DIR${NC}"
        echo -e "${YELLOW}Warning: Not in 90daydata project directory. Using fallback.${NC}"
    fi
fi

# Set up paths
BASE_DIR="/90daydata/$PROJECT_NAME/$USER_DIR"
STORAGE_PATH="$BASE_DIR/ollama"
CONTAINER_PATH="$BASE_DIR/ollama_latest.sif"
APPTAINER_CACHE_DIR="$BASE_DIR/apptainer_cache"

# Step 1: Load modules
echo -e "\n${BLUE}Step 2: Loading required modules...${NC}"
module load cuda cudnn apptainer

# Step 2: GPU Detection and Configuration
if ! detect_gpus; then
    echo -e "${RED}GPU detection failed. Exiting.${NC}"
    exit 1
fi

# Step 3: Setup directories
echo -e "\n${BLUE}Step 3: Setting up directories...${NC}"
mkdir -p "$BASE_DIR" "$STORAGE_PATH/models" "$STORAGE_PATH/cache" "$APPTAINER_CACHE_DIR"
chmod -R 755 "$BASE_DIR"

export APPTAINER_CACHEDIR="$APPTAINER_CACHE_DIR"
export APPTAINER_TMPDIR="$APPTAINER_CACHE_DIR/tmp"
mkdir -p "$APPTAINER_CACHE_DIR/tmp"

if [ ! -L "$HOME/.ollama" ] || [ "$(readlink "$HOME/.ollama")" != "$STORAGE_PATH" ]; then
    rm -rf "$HOME/.ollama"
    ln -s "$STORAGE_PATH" "$HOME/.ollama"
fi

# Step 4: Check container
echo -e "\n${BLUE}Step 4: Checking Ollama container...${NC}"
if [ ! -f "$CONTAINER_PATH" ]; then
    echo -e "${YELLOW}Downloading Ollama container...${NC}"
    cd "$BASE_DIR"
    apptainer pull docker://ollama/ollama:latest
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download container${NC}"
        exit 1
    fi
fi

# Step 5: GPU environment setup
GPU_LIST=""
for ((i=0; i<$NUM_GPUS; i++)); do
    if [ $i -gt 0 ]; then GPU_LIST="$GPU_LIST,"; fi
    GPU_LIST="$GPU_LIST$i"
done

echo -e "\n${BLUE}GPU Configuration for Ollama:${NC}"
echo -e "CUDA_VISIBLE_DEVICES: ${GREEN}$GPU_LIST${NC}"
echo -e "OLLAMA_NUM_GPU: ${GREEN}$NUM_GPUS${NC}"

# Create interactive session script
echo -e "\n${BLUE}Step 5: Creating interactive session script...${NC}"

cat > "$STORAGE_PATH/interactive_session.sh" << 'EOF'
#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Config will be replaced by parent script
MODEL_NAME="REPLACE_MODEL_NAME"
NUM_GPUS=REPLACE_NUM_GPUS
CONTEXT_SIZE=REPLACE_CONTEXT_SIZE
GPU_LIST="REPLACE_GPU_LIST"

echo -e "${BLUE}Starting USDA-ARS SCINet Interactive LLM Session...${NC}"
echo -e "Model: $MODEL_NAME"
echo -e "Context size: $CONTEXT_SIZE tokens"
echo -e "GPUs: $GPU_LIST"

# Step 1: GPU setup
echo -e "${BLUE}Setting GPU environment...${NC}"
export CUDA_VISIBLE_DEVICES=$GPU_LIST
export OLLAMA_NUM_GPU=$NUM_GPUS
export OLLAMA_GPU_LAYERS=999999
export OLLAMA_HOST=127.0.0.1:11434

echo -e "${BLUE}GPU Environment Set:${NC}"
echo -e "  CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo -e "  OLLAMA_NUM_GPU: $OLLAMA_NUM_GPU"

# Check GPU memory before starting
echo -e "${BLUE}GPU Memory Check:${NC}"
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv,noheader,nounits | \
while IFS=, read -r index used free; do
    echo -e "  GPU $index: ${GREEN}$free MB free${NC}, $used MB used"
done

# Step 2: Start Ollama server
echo -e "${BLUE}Starting Ollama server...${NC}"
ollama serve > /tmp/ollama_interactive.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to initialize
echo "Waiting for server to start..."
sleep 10

# Verify server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo -e "${RED}Server failed to start. Log:${NC}"
    cat /tmp/ollama_interactive.log
    exit 1
fi

echo -e "${GREEN}Ollama server started successfully${NC}"

# Step 3: Setup model
echo -e "${BLUE}Checking/downloading model $MODEL_NAME...${NC}"
if ! ollama list | grep -q "$MODEL_NAME"; then
    echo -e "${YELLOW}Model $MODEL_NAME not found. Downloading...${NC}"
    ollama pull "$MODEL_NAME"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download model${NC}"
        kill $SERVER_PID
        exit 1
    fi
fi

# Step 4: Create custom model with proper context window
CUSTOM_MODEL_NAME="${MODEL_NAME}_ctx${CONTEXT_SIZE}"

echo -e "${BLUE}Creating custom model with context window $CONTEXT_SIZE...${NC}"

# Create Modelfile for custom context
cat > /tmp/Modelfile_custom << MODELFILE_END
FROM $MODEL_NAME
PARAMETER num_ctx $CONTEXT_SIZE
MODELFILE_END

# Create the custom model
ollama create "$CUSTOM_MODEL_NAME" -f /tmp/Modelfile_custom

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Failed to create custom model, using original...${NC}"
    CUSTOM_MODEL_NAME="$MODEL_NAME"
fi

# Step 5: Verify context window setting
echo -e "${BLUE}Verifying context window is set to $CONTEXT_SIZE...${NC}"
ollama show "$CUSTOM_MODEL_NAME" | grep "num_ctx" || echo "Context window: $CONTEXT_SIZE (set via custom model)"

# Step 6: Show interactive instructions
echo -e "\n${GREEN}===============================================${NC}"
echo -e "${GREEN}🚀 INTERACTIVE SESSION READY 🚀${NC}"
echo -e "${GREEN}===============================================${NC}"
echo -e "${BLUE}Model: ${GREEN}$CUSTOM_MODEL_NAME${NC}"
echo -e "${BLUE}Context: ${GREEN}$CONTEXT_SIZE tokens${NC}"
echo -e "${BLUE}GPUs: ${GREEN}$NUM_GPUS ($GPU_LIST)${NC}"
echo ""
echo -e "${YELLOW}📋 Available Commands:${NC}"
echo -e "  ${BLUE}ollama run $CUSTOM_MODEL_NAME${NC}     - Start interactive chat"
echo -e "  ${BLUE}ollama list${NC}                      - List available models"
echo -e "  ${BLUE}ollama show $CUSTOM_MODEL_NAME${NC}   - Show model info"
echo -e "  ${BLUE}exit${NC}                            - Exit session"
echo ""
echo -e "${YELLOW}💡 Usage Tips:${NC}"
echo "• Use 'ollama run $CUSTOM_MODEL_NAME' to start chatting"
echo "• Type '/bye' in chat to exit the model"
echo "• Use Ctrl+C to stop current operation"
echo "• Context window is set to $CONTEXT_SIZE tokens"
echo ""
echo -e "${YELLOW}🔧 Advanced Options:${NC}"
echo "• Add parameters: ollama run $CUSTOM_MODEL_NAME --parameter temperature 0.8"
echo "• Show model details: ollama show $CUSTOM_MODEL_NAME"
echo "• List all models: ollama list"
echo ""

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    if [ -n "$SERVER_PID" ] && ps -p $SERVER_PID > /dev/null; then
        echo "Stopping Ollama server (PID: $SERVER_PID)..."
        kill $SERVER_PID
        sleep 2
    fi
    echo -e "${GREEN}Session ended. Goodbye!${NC}"
    exit 0
}

# Set up signal handling
trap cleanup SIGINT SIGTERM

# Step 7: Start interactive shell
echo -e "${GREEN}Starting interactive shell...${NC}"
echo -e "${BLUE}Hint: Try 'ollama run $CUSTOM_MODEL_NAME' to start chatting!${NC}"
echo ""

# Export environment for subshells
export CUSTOM_MODEL_NAME
export OLLAMA_HOST
export CUDA_VISIBLE_DEVICES
export OLLAMA_NUM_GPU

# Start bash with custom prompt
export PS1="\[\e[1;34m\][Ollama-$CUSTOM_MODEL_NAME]\[\e[0m\] \[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;36m\]\w\[\e[0m\]\$ "

# Function to display help
ollama_help() {
    echo -e "${BLUE}Quick Help:${NC}"
    echo "  ollama run $CUSTOM_MODEL_NAME    - Start chat"
    echo "  ollama list                     - List models"
    echo "  ollama show $CUSTOM_MODEL_NAME  - Model info"
    echo "  exit                           - Exit session"
}

# Make help function available
export -f ollama_help

# Show initial help
ollama_help

# Start interactive bash session
exec bash --noprofile --norc
EOF

# Replace variables in the script
sed -i "s/REPLACE_MODEL_NAME/$MODEL_NAME/g" "$STORAGE_PATH/interactive_session.sh"
sed -i "s/REPLACE_NUM_GPUS/$NUM_GPUS/g" "$STORAGE_PATH/interactive_session.sh"
sed -i "s/REPLACE_CONTEXT_SIZE/$CONTEXT_SIZE/g" "$STORAGE_PATH/interactive_session.sh"
sed -i "s/REPLACE_GPU_LIST/$GPU_LIST/g" "$STORAGE_PATH/interactive_session.sh"

chmod +x "$STORAGE_PATH/interactive_session.sh"

# Show preview and confirm
echo -e "\n${BLUE}Ready to start interactive session${NC}"
echo -e "\n${YELLOW}Configuration Summary:${NC}"
echo -e "Model: ${GREEN}$MODEL_NAME${NC} (with $CONTEXT_SIZE token context)"
echo -e "GPUs: ${GREEN}$NUM_GPUS ($GPU_LIST)${NC}"
echo -e "Container: ${GREEN}$CONTAINER_PATH${NC}"
echo -e "Storage: ${GREEN}$STORAGE_PATH${NC}"

echo -e "\n${YELLOW}Interactive Features:${NC}"
echo "• Direct CLI access to ollama commands"
echo "• Custom model with your specified context size"
echo "• GPU-optimized environment"
echo "• Clean terminal with helpful prompts"
echo "• Signal handling for clean shutdown"

if [[ "$AUTO_RUN" != "true" ]]; then
    echo -e "\n${YELLOW}Press Enter to start interactive session...${NC}"
    read
else
    echo -e "\n${GREEN}Auto-run mode enabled - starting session...${NC}"
    sleep 2
fi

# Execute interactive session
echo -e "${GREEN}Starting interactive session...${NC}"

apptainer exec --nv --cleanenv \
    --env OLLAMA_HOME=/root/.ollama \
    --env CUDA_VISIBLE_DEVICES=$GPU_LIST \
    --env OLLAMA_NUM_GPU=$NUM_GPUS \
    --env OLLAMA_GPU_LAYERS=999999 \
    -B "$STORAGE_PATH:/root/.ollama" \
    "$CONTAINER_PATH" /root/.ollama/interactive_session.sh

echo -e "\n${BLUE}Interactive session ended.${NC}"
echo -e "${GREEN}Thanks for using USDA-ARS SCINet Atlas LLM Interactive Session!${NC}"