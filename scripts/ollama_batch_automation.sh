#!/bin/bash
#
# ollama_batch_automation.sh
# Version: 3.0
# Purpose: USDA-ARS SCINet Atlas LLM Batch Processor with Reasoning Support
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
DEFAULT_CONTEXT_SIZE=8192  # 8k tokens - safe default for most models
PROJECT_NAME="lemay_diet_guthealth"

# Initialize variables
MODEL_NAME=""
INPUT_DIR=""
OUTPUT_DIR=""
NUM_GPUS=""
CONTEXT_SIZE=""
REASONING_MODE=false
AUTO_RUN=false
USER_SUBDIR=""

# Function to show usage
show_usage() {
    echo -e "${BLUE}==== USDA-ARS SCINet Atlas LLM Batch Processor ====${NC}"
    echo -e "${BLUE}Version 3.0 - Created by Richard Stoker for USDA-ARS HPC${NC}"
    echo -e "${GREEN}Contact: richard.stoker@usda.gov${NC}"
    echo -e "${GREEN}GitHub: https://github.com/RichardStoker-USDA${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "$0 [model_name] [input_dir] [output_dir] [num_gpus] [ctx_size] [flags]"
    echo ""
    echo -e "${YELLOW}Parameters:${NC}"
    echo "  model_name    - Ollama model name (default: $DEFAULT_MODEL)"
    echo "  input_dir     - Directory with .txt prompt files (default: ./input_prompts)"
    echo "  output_dir    - Output directory (default: ./results)"
    echo "  num_gpus      - Number of GPUs to use (default: auto-detect)"
    echo "  ctx_size      - Context window size in tokens (default: $DEFAULT_CONTEXT_SIZE)"
    echo ""
    echo -e "${YELLOW}Optional Flags:${NC}"
    echo "  -r, --reasoning    Enable reasoning mode for supported models"
    echo "  -s, --skip         Skip all confirmations (auto-run mode)"
    echo "  -u, --user-dir DIR Custom user subdirectory"
    echo "  -h, --help         Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  # Basic usage with small model"
    echo "  $0 gemma3:1b ./prompts ./results 1 8192"
    echo ""
    echo "  # With reasoning mode enabled"
    echo "  $0 deepseek-r1:8b ./data ./output 2 32768 -r"
    echo ""
    echo "  # Large model with moderate context"
    echo "  $0 llama3.3:70b ./research ./analysis 6 32768 -s"
    echo ""
    echo "  # Full features: reasoning + auto-run + custom dir"
    echo "  $0 deepseek-r1:8b ./complex_data ./results 3 16384 -r -s -u custom_dir"
    echo ""
    echo -e "${YELLOW}Reasoning Models Available in Ollama:${NC}"
    echo "• deepseek-r1:8b (DeepSeek reasoning model - 8B parameters)"
    echo "• deepseek-r1:latest (DeepSeek reasoning model - latest version)"
    echo "• cogito:latest (Deep Cogito hybrid reasoning model)"
    echo "• cogito:7b (Deep Cogito 7B reasoning model)"
    echo ""
    echo -e "${YELLOW}GPU Detection:${NC}"
    echo "• Script auto-detects available NVIDIA GPUs using nvidia-smi"
    echo "• Ensures proper load balancing across multiple A100 GPUs"
    echo "• Override detection by specifying num_gpus parameter"
    echo ""
    echo -e "${YELLOW}Data Support:${NC}"
    echo "• Tab-delimited files (.tsv, .csv converted to .txt)"
    echo "• Large documents (up to context window size)"
    echo "• Multi-file batch processing with synthesis"
}

# Parse command line arguments
parse_args() {
    # Set defaults
    MODEL_NAME="$DEFAULT_MODEL"
    INPUT_DIR="./input_prompts"
    OUTPUT_DIR="./results"
    NUM_GPUS="auto"
    CONTEXT_SIZE="$DEFAULT_CONTEXT_SIZE"
    
    # Parse positional arguments first
    if [ $# -ge 1 ] && [[ ! "$1" =~ ^- ]]; then
        MODEL_NAME="$1"
        shift
    fi
    
    if [ $# -ge 1 ] && [[ ! "$1" =~ ^- ]]; then
        INPUT_DIR="$1"
        shift
    fi
    
    if [ $# -ge 1 ] && [[ ! "$1" =~ ^- ]]; then
        OUTPUT_DIR="$1"
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
            -r|--reasoning)
                REASONING_MODE=true
                shift
                ;;
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
    echo -e "\n${BLUE}Step 0: Detecting available NVIDIA GPUs...${NC}"
    
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

echo -e "${BLUE}==== USDA-ARS SCINet Atlas LLM Batch Processor ====${NC}"
echo -e "${BLUE}Version 3.0 - Created by Richard Stoker for USDA-ARS HPC${NC}"
echo -e "${GREEN}Contact: richard.stoker@usda.gov${NC}"
echo -e "${GREEN}GitHub: https://github.com/RichardStoker-USDA${NC}"

echo -e "\n${BLUE}Configuration:${NC}"
echo -e "Model: ${GREEN}$MODEL_NAME${NC}"
echo -e "Context size: ${GREEN}$CONTEXT_SIZE tokens${NC}"
echo -e "Input directory: ${GREEN}$INPUT_DIR${NC}"
echo -e "Output directory: ${GREEN}$OUTPUT_DIR${NC}"
echo -e "Reasoning mode: ${GREEN}$REASONING_MODE${NC}"
echo -e "Auto-run mode: ${GREEN}$AUTO_RUN${NC}"

# Detect if model supports reasoning based on name patterns
SUPPORTS_REASONING=false
if [[ "$MODEL_NAME" =~ (deepseek-r1|cogito|reasoning|think) ]]; then
    SUPPORTS_REASONING=true
    echo -e "${YELLOW}Reasoning model detected: $MODEL_NAME${NC}"
elif [[ "$REASONING_MODE" == "true" ]]; then
    echo -e "${YELLOW}Warning: Reasoning mode requested for model that may not support it${NC}"
    SUPPORTS_REASONING=true
fi

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

# Validate inputs
if [ ! -d "$INPUT_DIR" ]; then
    echo -e "${RED}Error: Input directory $INPUT_DIR does not exist${NC}"
    show_usage
    exit 1
fi

txt_count=$(find "$INPUT_DIR" -name "*.txt" -type f | wc -l)
if [ $txt_count -eq 0 ]; then
    echo -e "${RED}Error: No .txt files found in $INPUT_DIR${NC}"
    exit 1
fi

echo -e "\n${BLUE}Found $txt_count .txt files to process${NC}"

# Check for large files and give guidance
total_size=$(find "$INPUT_DIR" -name "*.txt" -exec wc -c {} + | tail -1 | awk '{print $1}' 2>/dev/null || echo 0)
if [ $total_size -gt 1000000 ]; then
    echo -e "${YELLOW}Large data detected: $(echo "scale=1; $total_size/1024/1024" | bc 2>/dev/null || echo "?")MB total${NC}"
    echo -e "${YELLOW}Models can analyze tab-delimited data, CSV files, and large documents${NC}"
    echo -e "${YELLOW}Consider reasoning mode for complex data analysis tasks${NC}"
fi

mkdir -p "$OUTPUT_DIR"

# Step 1: Load modules
echo -e "\n${BLUE}Step 1: Loading required modules...${NC}"
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

# Step 6: Create enhanced folder structure with timestamps
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BATCH_DIR="$OUTPUT_DIR/batch_$TIMESTAMP"
ANALYSIS_DIR="$BATCH_DIR/analysis_outputs"
PROMPTS_ARCHIVE_DIR="$BATCH_DIR/prompts_archive"
BATCH_LOGS_DIR="$BATCH_DIR/batch_info"

# Check for synthesis mode to create appropriate folders
SYNTHESIS_MODE=0
if [ -f "$INPUT_DIR/synthesis_question.txt" ]; then
    SYNTHESIS_MODE=1
    SYNTHESIS_DIR="$BATCH_DIR/synthesis_analysis"
    mkdir -p "$SYNTHESIS_DIR"
fi

# Check for reasoning mode to create reasoning folders
if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" ]]; then
    REASONING_DIR="$BATCH_DIR/reasoning_outputs"
    mkdir -p "$REASONING_DIR"
fi

echo -e "\n${BLUE}Step 5: Creating organized batch directory structure...${NC}"
mkdir -p "$ANALYSIS_DIR" "$PROMPTS_ARCHIVE_DIR" "$BATCH_LOGS_DIR"

echo -e "${GREEN}Batch structure created:${NC}"
echo -e "  Batch Directory: ${BATCH_DIR}/"
echo -e "     batch_info/ (summary, logs, technical details)"
echo -e "     analysis_outputs/ (individual file results)"
echo -e "     prompts_archive/ (copy of all input prompts)"
if [ $SYNTHESIS_MODE -eq 1 ]; then
    echo -e "     synthesis_analysis/ (meta-analysis results)"
fi
if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" ]]; then
    echo -e "     reasoning_outputs/ (thinking processes)"
fi

# Copy all prompt files for archival
echo -e "${BLUE}Archiving prompt files for record keeping...${NC}"
cp "$INPUT_DIR"/*.txt "$PROMPTS_ARCHIVE_DIR/" 2>/dev/null || echo "No .txt files to archive"

# Step 7: Create enhanced batch processing script
echo -e "\n${BLUE}Step 6: Creating enhanced batch processing script...${NC}"

cat > "$STORAGE_PATH/automated_batch_enhanced.sh" << 'EOF'
#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Config will be replaced by parent script
MODEL_NAME="REPLACE_MODEL_NAME"
INPUT_DIR="/input"
OUTPUT_DIR="/output"
NUM_GPUS=REPLACE_NUM_GPUS
CONTEXT_SIZE=REPLACE_CONTEXT_SIZE
GPU_LIST="REPLACE_GPU_LIST"
BATCH_TIMESTAMP="REPLACE_BATCH_TIMESTAMP"
REASONING_MODE="REPLACE_REASONING_MODE"
SUPPORTS_REASONING="REPLACE_SUPPORTS_REASONING"
AUTO_RUN="REPLACE_AUTO_RUN"

echo -e "${BLUE}Starting USDA-ARS SCINet LLM batch processing...${NC}"
echo -e "Model: $MODEL_NAME"
echo -e "Context size: $CONTEXT_SIZE tokens"
echo -e "GPUs: $GPU_LIST"
echo -e "Batch ID: $BATCH_TIMESTAMP"
echo -e "Reasoning mode: $REASONING_MODE"
echo -e "Auto-run mode: $AUTO_RUN"

# Enhanced output cleaning function
clean_ollama_output() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        return 1
    fi
    
    # Comprehensive cleaning pipeline for Ollama output
    cat "$input_file" | \
    # Remove ANSI escape sequences
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | \
    # Remove specific Ollama progress indicators
    sed 's/\[?[0-9]*[hlHLK]//g' | \
    sed 's/\[?[0-9]*l//g' | \
    sed 's/\[?[0-9]*h//g' | \
    # Remove Unicode spinner characters (Braille patterns)
    sed 's/⠋//g; s/⠙//g; s/⠹//g; s/⠸//g; s/⠼//g; s/⠴//g; s/⠦//g; s/⠧//g; s/⠇//g; s/⠏//g' | \
    # Remove carriage returns and other control chars
    tr -d '\r' | \
    tr -d '\f' | \
    # Remove lines that are just whitespace or control sequences
    grep -v '^[[:space:]]*$' | \
    # Remove common Ollama status messages
    grep -v "^pulling manifest" | \
    grep -v "^verifying sha256" | \
    grep -v "^writing manifest" | \
    grep -v "^removing any unused layers" | \
    # Remove any remaining escape sequences
    sed 's/\[\([0-9]\{1,2\}\(;[0-9]\{1,2\}\)\?\)\?[mGK]//g' | \
    # Clean up multiple consecutive newlines
    sed '/^$/N;/^\n$/d' > "$output_file"
    
    # If file is empty or too small, it likely failed
    if [ ! -s "$output_file" ] || [ $(wc -c < "$output_file") -lt 10 ]; then
        return 1
    fi
    
    return 0
}

# Step 1: GPU setup with enhanced logging
echo -e "${BLUE}Setting GPU environment...${NC}"
export CUDA_VISIBLE_DEVICES=$GPU_LIST
export OLLAMA_NUM_GPU=$NUM_GPUS
export OLLAMA_GPU_LAYERS=999999
export OLLAMA_HOST=127.0.0.1:11434

# Enhanced environment for clean output
export OLLAMA_NOHISTORY=1
export TERM=dumb
export OLLAMA_DEBUG=0
export NO_COLOR=1

echo -e "${BLUE}GPU Environment Set:${NC}"
echo -e "  CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo -e "  OLLAMA_NUM_GPU: $OLLAMA_NUM_GPU"
echo -e "  GPU Memory Check..."

# Check GPU memory before starting
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv,noheader,nounits | \
while IFS=, read -r index used free; do
    echo -e "  GPU $index: ${GREEN}$free MB free${NC}, $used MB used"
done

# Step 2: Start Ollama server
echo -e "${BLUE}Starting Ollama server...${NC}"
ollama serve > /tmp/ollama_batch.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to initialize
echo "Waiting for server to start..."
sleep 10

# Verify server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo -e "${RED}Server failed to start. Log:${NC}"
    cat /tmp/ollama_batch.log
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

# Step 6: Process all text files
echo -e "${GREEN}Starting batch processing...${NC}"
processed=0
failed=0
start_time=$(date +%s)

# Check if synthesis mode is enabled
SYNTHESIS_MODE=${SYNTHESIS_MODE:-0}

# Ensure reasoning directory exists if needed
if [[ "$REASONING_MODE" == "true" && "$SUPPORTS_REASONING" == "true" ]]; then
    mkdir -p "$OUTPUT_DIR/reasoning_outputs"
    echo -e "${BLUE}Created reasoning outputs directory${NC}"
fi

# Get total count for progress (exclude synthesis_question.txt)
txt_count=$(find "$INPUT_DIR" -name "*.txt" -type f ! -name "synthesis_question.txt" | wc -l)

# Create enhanced summary file in batch_info directory
SUMMARY_FILE="$OUTPUT_DIR/batch_info/batch_summary_$BATCH_TIMESTAMP.txt"
TECH_LOG_FILE="$OUTPUT_DIR/batch_info/technical_log_$BATCH_TIMESTAMP.txt"

mkdir -p "$OUTPUT_DIR/batch_info"

# Enhanced summary file with new features
echo "===============================================" > "$SUMMARY_FILE"
echo "USDA-ARS SCINET ATLAS LLM BATCH PROCESSING SUMMARY" >> "$SUMMARY_FILE"
echo "===============================================" >> "$SUMMARY_FILE"
echo "Script Version: 3.0" >> "$SUMMARY_FILE"
echo "Created by: Richard Stoker (richard.stoker@usda.gov)" >> "$SUMMARY_FILE"
echo "GitHub: https://github.com/RichardStoker-USDA" >> "$SUMMARY_FILE"
echo "Batch ID: $BATCH_TIMESTAMP" >> "$SUMMARY_FILE"
echo "Started: $(date)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "MODEL CONFIGURATION:" >> "$SUMMARY_FILE"
echo "Original Model: $MODEL_NAME" >> "$SUMMARY_FILE"
echo "Custom Model: $CUSTOM_MODEL_NAME" >> "$SUMMARY_FILE"
echo "Context Size: $CONTEXT_SIZE tokens" >> "$SUMMARY_FILE"
echo "Reasoning Mode: $REASONING_MODE" >> "$SUMMARY_FILE"
echo "Auto-run Mode: $AUTO_RUN" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "HARDWARE CONFIGURATION:" >> "$SUMMARY_FILE"
echo "GPUs Used: $GPU_LIST" >> "$SUMMARY_FILE"
echo "Total GPU Count: $NUM_GPUS" >> "$SUMMARY_FILE"
echo "CUDA Devices: $CUDA_VISIBLE_DEVICES" >> "$SUMMARY_FILE"
echo "Total Input Files: $txt_count" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Enhanced technical log file
echo "===============================================" > "$TECH_LOG_FILE"
echo "TECHNICAL PROCESSING LOG - VERSION 3.0" >> "$TECH_LOG_FILE"
echo "===============================================" >> "$TECH_LOG_FILE"
echo "Batch ID: $BATCH_TIMESTAMP" >> "$TECH_LOG_FILE"
echo "Started: $(date)" >> "$TECH_LOG_FILE"
echo "Server PID: $SERVER_PID" >> "$TECH_LOG_FILE"
echo "Reasoning Support: $SUPPORTS_REASONING" >> "$TECH_LOG_FILE"
echo "Reasoning Mode Enabled: $REASONING_MODE" >> "$TECH_LOG_FILE"
echo "Auto-run Mode: $AUTO_RUN" >> "$TECH_LOG_FILE"
echo "" >> "$TECH_LOG_FILE"
echo "ENVIRONMENT VARIABLES:" >> "$TECH_LOG_FILE"
echo "  CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES" >> "$TECH_LOG_FILE"
echo "  OLLAMA_NUM_GPU: $OLLAMA_NUM_GPU" >> "$TECH_LOG_FILE"
echo "  OLLAMA_NOHISTORY: $OLLAMA_NOHISTORY" >> "$TECH_LOG_FILE"
echo "  TERM: $TERM" >> "$TECH_LOG_FILE"
echo "  NO_COLOR: $NO_COLOR" >> "$TECH_LOG_FILE"
echo "" >> "$TECH_LOG_FILE"
echo "GPU MEMORY STATUS (START):" >> "$TECH_LOG_FILE"
nvidia-smi --query-gpu=index,name,memory.used,memory.free --format=csv,noheader,nounits >> "$TECH_LOG_FILE"
echo "" >> "$TECH_LOG_FILE"

for input_file in "$INPUT_DIR"/*.txt; do
    # Check if file exists
    if [ ! -f "$input_file" ]; then
        echo -e "${YELLOW}No .txt files found in $INPUT_DIR${NC}"
        break
    fi
    
    # Get filename
    filename=$(basename "$input_file")
    name_only="${filename%.*}"
    
    # Skip synthesis_question.txt in regular processing
    if [ "$filename" = "synthesis_question.txt" ]; then
        echo -e "${BLUE}Skipping synthesis_question.txt (will process in synthesis mode)${NC}"
        continue
    fi
    
    output_file="$OUTPUT_DIR/analysis_outputs/${name_only}_result.txt"
    reasoning_output_file="$OUTPUT_DIR/reasoning_outputs/${name_only}_thinking.txt"
    
    echo -e "${BLUE}Processing [$((processed + failed + 1))/$txt_count]: $filename${NC}"
    
    # Log processing start
    echo "PROCESSING: $filename ($(date))" >> "$TECH_LOG_FILE"
    
    # Read prompt safely
    prompt=$(cat "$input_file")
    
    if [ -z "$prompt" ]; then
        echo -e "${YELLOW}Warning: $filename is empty, skipping${NC}"
        echo "  SKIPPED: Empty file" >> "$TECH_LOG_FILE"
        continue
    fi
    
    # Log file info
    file_size=$(wc -c < "$input_file")
    echo "  File size: $file_size bytes" >> "$TECH_LOG_FILE"
    
    # Process each file
    file_start=$(date +%s)
    
    echo -e "${YELLOW}Running inference...${NC}"
    
    # Method 1: Try API approach first (usually cleaner)
    api_success=0
    echo "$prompt" > /tmp/current_prompt.txt
    
    # Try API if server responds to ping
    if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        echo "  Attempting API method..." >> "$TECH_LOG_FILE"
        
        # Create JSON payload safely
        python3 -c "
import json
import sys
with open('/tmp/current_prompt.txt', 'r') as f:
    prompt = f.read()
payload = {
    'model': '$CUSTOM_MODEL_NAME',
    'prompt': prompt,
    'stream': False,
    'options': {
        'num_ctx': $CONTEXT_SIZE
    }
}
print(json.dumps(payload))
" > /tmp/api_payload.json
        
        if curl -s -X POST http://127.0.0.1:11434/api/generate \
            -H "Content-Type: application/json" \
            -d @/tmp/api_payload.json | \
            python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('response', ''))" > "$output_file.tmp" 2>/dev/null; then
            
            if [ -s "$output_file.tmp" ]; then
                mv "$output_file.tmp" "$output_file"
                api_success=1
                echo "  API method successful" >> "$TECH_LOG_FILE"
            fi
        fi
        
        rm -f /tmp/api_payload.json
    fi
    
    # Method 2: Fallback to CLI if API failed
    if [ $api_success -eq 0 ]; then
        echo "  API failed, using CLI method..." >> "$TECH_LOG_FILE"
        
        # Enhanced CLI method with multiple cleaning passes
        timeout 300 bash -c '
            export TERM=dumb
            export OLLAMA_NOHISTORY=1
            export NO_COLOR=1
            cat /tmp/current_prompt.txt | ollama run "$1" 2>/dev/null
        ' -- "$CUSTOM_MODEL_NAME" > "$output_file.raw" 2>&1
        
        # Apply enhanced cleaning
        if clean_ollama_output "$output_file.raw" "$output_file"; then
            echo "  CLI method successful after cleaning" >> "$TECH_LOG_FILE"
        else
            echo "  CLI method failed" >> "$TECH_LOG_FILE"
            echo "Error: Unable to generate clean output for $filename" > "$output_file"
            echo "Original prompt: $prompt" >> "$output_file"
        fi
        
        rm -f "$output_file.raw"
    fi
    
    # Clean up temp files
    rm -f /tmp/current_prompt.txt
    
    # Step 2: Process reasoning output if reasoning mode enabled
    reasoning_success=0
    if [[ "$REASONING_MODE" == "true" && "$SUPPORTS_REASONING" == "true" ]]; then
        echo -e "${YELLOW}Extracting reasoning process...${NC}"
        echo "  Processing reasoning mode..." >> "$TECH_LOG_FILE"
        
        # Ensure reasoning directory exists before processing
        mkdir -p "$(dirname "$reasoning_output_file")"
        
        # Create reasoning-specific prompt
        reasoning_prompt="$prompt

Please show your step-by-step thinking process for this analysis. Use <thinking> tags to show your reasoning before providing the final answer."
        
        echo "$reasoning_prompt" > /tmp/reasoning_prompt.txt
        
        # Try to get reasoning output
        timeout 300 bash -c '
            export TERM=dumb
            export OLLAMA_NOHISTORY=1
            export NO_COLOR=1
            cat /tmp/reasoning_prompt.txt | ollama run "$1" 2>/dev/null
        ' -- "$CUSTOM_MODEL_NAME" > "$reasoning_output_file.raw" 2>&1
        
        # Extract thinking content if present
        if [ -f "$reasoning_output_file.raw" ]; then
            # Try to extract <thinking> content
            if grep -q "<thinking>" "$reasoning_output_file.raw"; then
                sed -n '/<thinking>/,/<\/thinking>/p' "$reasoning_output_file.raw" | \
                clean_ollama_output /dev/stdin "$reasoning_output_file"
                reasoning_success=1
                echo "  Reasoning extracted successfully (with thinking tags)" >> "$TECH_LOG_FILE"
            else
                # If no explicit thinking tags, try to detect reasoning patterns
                if clean_ollama_output "$reasoning_output_file.raw" "$reasoning_output_file"; then
                    reasoning_success=1
                    echo "  Reasoning output processed (no explicit tags)" >> "$TECH_LOG_FILE"
                fi
            fi
            rm -f "$reasoning_output_file.raw"
        fi
        
        rm -f /tmp/reasoning_prompt.txt
        
        if [ $reasoning_success -eq 0 ]; then
            echo "No reasoning process detected or model doesn't support reasoning" > "$reasoning_output_file"
            echo "  Reasoning extraction failed" >> "$TECH_LOG_FILE"
        fi
    fi
    
    # Check if processing was successful
    if [ -s "$output_file" ] && [ $(wc -c < "$output_file") -gt 20 ]; then
        file_end=$(date +%s)
        duration=$((file_end - file_start))
        output_size=$(wc -c < "$output_file")
        echo -e "${GREEN}Completed $filename in ${duration}s${NC}"
        
        # Add to summary
        echo "SUCCESS: $filename -> ${name_only}_result.txt (${duration}s, ${output_size} bytes)" >> "$SUMMARY_FILE"
        echo "  SUCCESS: $filename processed in ${duration}s, output: ${output_size} bytes" >> "$TECH_LOG_FILE"
        
        # Add reasoning info if applicable
        if [[ "$REASONING_MODE" == "true" && "$SUPPORTS_REASONING" == "true" && $reasoning_success -eq 1 ]]; then
            reasoning_size=$(wc -c < "$reasoning_output_file")
            echo "  REASONING: ${reasoning_size} bytes of thinking process captured" >> "$TECH_LOG_FILE"
        fi
        
        ((processed++))
    else
        echo -e "${RED}Failed to process $filename${NC}"
        echo "Error: No valid output generated for $filename" > "$output_file"
        echo "Prompt was: $prompt" >> "$output_file"
        echo "FAILED: $filename -> FAILED" >> "$SUMMARY_FILE"
        echo "  FAILED: $filename - no valid output generated" >> "$TECH_LOG_FILE"
        ((failed++))
    fi
    
    # Show progress
    total=$((processed + failed))
    remaining=$((txt_count - total))
    echo -e "${BLUE}Progress: $total/$txt_count files processed, $remaining remaining${NC}"
done

# Final summary
end_time=$(date +%s)
total_duration=$((end_time - start_time))

echo -e "\n${BLUE}=== Batch Processing Complete ===${NC}"
echo -e "${GREEN}Successfully processed: $processed files${NC}"
if [ $failed -gt 0 ]; then
    echo -e "${RED}Failed: $failed files${NC}"
fi
echo -e "${BLUE}Total time: ${total_duration}s${NC}"

# Update summary files with enhanced details
echo "" >> "$SUMMARY_FILE"
echo "===============================================" >> "$SUMMARY_FILE"
echo "FINAL RESULTS" >> "$SUMMARY_FILE"
echo "===============================================" >> "$SUMMARY_FILE"
echo "Completed: $(date)" >> "$SUMMARY_FILE"
echo "Total files processed: $processed" >> "$SUMMARY_FILE"
echo "Failed files: $failed" >> "$SUMMARY_FILE"
if [ $((processed + failed)) -gt 0 ]; then
    echo "Success rate: $(( processed * 100 / (processed + failed) ))%" >> "$SUMMARY_FILE"
    echo "Average time per file: $(( total_duration / (processed + failed) ))s" >> "$SUMMARY_FILE"
fi
echo "Total duration: ${total_duration}s" >> "$SUMMARY_FILE"

# Add reasoning summary if applicable
if [[ "$REASONING_MODE" == "true" && "$SUPPORTS_REASONING" == "true" ]]; then
    reasoning_files=$(find "$OUTPUT_DIR/reasoning_outputs" -name "*_thinking.txt" -type f 2>/dev/null | wc -l)
    echo "" >> "$SUMMARY_FILE"
    echo "REASONING ANALYSIS:" >> "$SUMMARY_FILE"
    echo "Reasoning files generated: $reasoning_files" >> "$SUMMARY_FILE"
    echo "Reasoning model: $MODEL_NAME" >> "$SUMMARY_FILE"
fi

echo "" >> "$TECH_LOG_FILE"
echo "Processing completed: $(date)" >> "$TECH_LOG_FILE"
echo "Final stats: $processed successful, $failed failed" >> "$TECH_LOG_FILE"
echo "" >> "$TECH_LOG_FILE"
echo "GPU MEMORY STATUS (END):" >> "$TECH_LOG_FILE"
nvidia-smi --query-gpu=index,name,memory.used,memory.free --format=csv,noheader,nounits >> "$TECH_LOG_FILE"

# Step 7: Synthesis mode
if [ "$SYNTHESIS_MODE" = "1" ] && [ -f "/synthesis_question.txt" ]; then
    echo -e "\n${BLUE}=== SYNTHESIS ANALYSIS MODE ===${NC}"
    
    synthesis_question=$(cat "/synthesis_question.txt")
    if [ -z "$synthesis_question" ]; then
        echo -e "${YELLOW}Warning: synthesis_question.txt is empty, skipping synthesis${NC}"
    else
        echo -e "${BLUE}Synthesis Question: $synthesis_question${NC}"
        
        # Token counting and setup
        total_chars=0
        result_files=()
        
        for result_file in "$OUTPUT_DIR/analysis_outputs"/*_result.txt; do
            if [ -f "$result_file" ]; then
                chars=$(wc -c < "$result_file")
                total_chars=$((total_chars + chars))
                result_files+=("$result_file")
            fi
        done
        
        # Token estimation
        estimated_tokens=$((total_chars / 4))
        context_available=$((CONTEXT_SIZE - 1000))
        
        echo -e "${BLUE}Synthesis setup:${NC}"
        echo -e "Total result files: ${#result_files[@]}"
        echo -e "Total characters: $total_chars"
        echo -e "Estimated tokens: $estimated_tokens"
        echo -e "Available context: $context_available"
        
        # Log synthesis attempt
        echo "SYNTHESIS ANALYSIS:" >> "$TECH_LOG_FILE"
        echo "  Question: $synthesis_question" >> "$TECH_LOG_FILE"
        echo "  Files: ${#result_files[@]}" >> "$TECH_LOG_FILE"
        echo "  Estimated tokens: $estimated_tokens" >> "$TECH_LOG_FILE"
        
        if [ $estimated_tokens -gt $context_available ]; then
            echo -e "${YELLOW}WARNING: Combined results may exceed context window${NC}"
            echo "  WARNING: Token count may exceed context window" >> "$TECH_LOG_FILE"
        fi
        
        # Build synthesis prompt
        echo -e "${BLUE}Creating synthesis context...${NC}"
        synthesis_input="/tmp/synthesis_input.txt"
        
        echo "SYNTHESIS QUESTION: $synthesis_question" > "$synthesis_input"
        echo "" >> "$synthesis_input"
        echo "ANALYSIS RESULTS TO SYNTHESIZE:" >> "$synthesis_input"
        echo "================================" >> "$synthesis_input"
        echo "" >> "$synthesis_input"
        
        # Add all results
        file_count=0
        for result_file in "${result_files[@]}"; do
            ((file_count++))
            filename=$(basename "$result_file")
            echo "--- RESULT $file_count: $filename ---" >> "$synthesis_input"
            cat "$result_file" >> "$synthesis_input"
            echo "" >> "$synthesis_input"
            echo "--- END RESULT $file_count ---" >> "$synthesis_input"
            echo "" >> "$synthesis_input"
        done
        
        echo "SYNTHESIS INSTRUCTION:" >> "$synthesis_input"
        echo "Based on all the analysis results above, please provide a comprehensive synthesis that addresses the original question: $synthesis_question" >> "$synthesis_input"
        
        # Run synthesis
        echo -e "${BLUE}Running synthesis analysis...${NC}"
        synthesis_start=$(date +%s)
        
        synthesis_output="$OUTPUT_DIR/synthesis_analysis/SYNTHESIS_FINAL_ANALYSIS.txt"
        mkdir -p "$OUTPUT_DIR/synthesis_analysis"
        
        # Use enhanced synthesis processing
        timeout 600 bash -c '
            export TERM=dumb
            export OLLAMA_NOHISTORY=1
            export NO_COLOR=1
            cat "$1" | ollama run "$2" 2>/dev/null
        ' -- "$synthesis_input" "$CUSTOM_MODEL_NAME" > "$synthesis_output.raw" 2>&1
        
        # Clean synthesis output
        if clean_ollama_output "$synthesis_output.raw" "$synthesis_output"; then
            synthesis_end=$(date +%s)
            synthesis_duration=$((synthesis_end - synthesis_start))
            synthesis_size=$(wc -c < "$synthesis_output")
            echo -e "${GREEN}Synthesis completed in ${synthesis_duration}s${NC}"
            echo -e "${GREEN}Synthesis saved to: synthesis_analysis/SYNTHESIS_FINAL_ANALYSIS.txt${NC}"
            
            # Update summary files
            echo "" >> "$SUMMARY_FILE"
            echo "===============================================" >> "$SUMMARY_FILE"
            echo "SYNTHESIS ANALYSIS" >> "$SUMMARY_FILE"
            echo "===============================================" >> "$SUMMARY_FILE"
            echo "Question: $synthesis_question" >> "$SUMMARY_FILE"
            echo "Files analyzed: ${#result_files[@]}" >> "$SUMMARY_FILE"
            echo "Total tokens (estimated): $estimated_tokens" >> "$SUMMARY_FILE"
            echo "Synthesis duration: ${synthesis_duration}s" >> "$SUMMARY_FILE"
            echo "Synthesis output size: ${synthesis_size} bytes" >> "$SUMMARY_FILE"
            echo "Output: synthesis_analysis/SYNTHESIS_FINAL_ANALYSIS.txt" >> "$SUMMARY_FILE"
            
            echo "  Synthesis completed successfully: ${synthesis_duration}s, ${synthesis_size} bytes" >> "$TECH_LOG_FILE"
        else
            echo -e "${RED}Synthesis failed - no valid output generated${NC}"
            echo "Synthesis: FAILED" >> "$SUMMARY_FILE"
            echo "  Synthesis failed - no valid output" >> "$TECH_LOG_FILE"
        fi
        
        rm -f "$synthesis_input" "$synthesis_output.raw"
    fi
fi

# Model verification
echo -e "${BLUE}Final verification - Model context info:${NC}"
ollama show "$CUSTOM_MODEL_NAME" | grep -E "(num_ctx|context)"

# Cleanup
echo -e "${BLUE}Stopping Ollama server...${NC}"
kill $SERVER_PID

echo -e "${GREEN}All done! Check organized output directories.${NC}"
exit 0
EOF

# Replace variables in the script using safe method
sed -i "s/REPLACE_MODEL_NAME/$MODEL_NAME/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_NUM_GPUS/$NUM_GPUS/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_CONTEXT_SIZE/$CONTEXT_SIZE/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_GPU_LIST/$GPU_LIST/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_BATCH_TIMESTAMP/$TIMESTAMP/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_REASONING_MODE/$REASONING_MODE/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_SUPPORTS_REASONING/$SUPPORTS_REASONING/g" "$STORAGE_PATH/automated_batch_enhanced.sh"
sed -i "s/REPLACE_AUTO_RUN/$AUTO_RUN/g" "$STORAGE_PATH/automated_batch_enhanced.sh"

chmod +x "$STORAGE_PATH/automated_batch_enhanced.sh"

# Step 8: Show preview and confirm
echo -e "\n${BLUE}Ready to process files${NC}"
echo -e "\n${BLUE}Files to process:${NC}"
ls -la "$INPUT_DIR"/*.txt | head -5

echo -e "\n${YELLOW}This will create:${NC}"
echo "Batch Directory: $BATCH_DIR/"
echo "   batch_info/"
echo "      batch_summary_$TIMESTAMP.txt (comprehensive summary)"
echo "      technical_log_$TIMESTAMP.txt (technical details & GPU info)"
echo "   analysis_outputs/ (individual results)"
echo "   prompts_archive/ (archived prompts)"
if [ $SYNTHESIS_MODE -eq 1 ]; then
    echo "   synthesis_analysis/ (meta-analysis)"
fi
if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" ]]; then
    echo "   reasoning_outputs/ (thinking processes)"
fi

echo -e "\n${YELLOW}Enhanced Features:${NC}"
echo "• GPU auto-detection and load balancing across A100s"
echo "• Enhanced output cleaning (removes ALL control characters)"
echo "• Dual API/CLI approach for maximum reliability"
echo "• Support for large tab-delimited data files"
echo "• Comprehensive logging with GPU monitoring"
echo "• Flag-based parameters for clarity"
if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" ]]; then
    echo "• Reasoning/thinking process extraction"
fi

if [[ "$AUTO_RUN" != "true" ]]; then
    echo -e "\n${YELLOW}Press Enter to start enhanced batch processing...${NC}"
    read
else
    echo -e "\n${GREEN}Auto-run mode enabled - starting immediately...${NC}"
    sleep 2
fi

# Step 9: Check for synthesis feature
SYNTHESIS_FILE=""
if [ -f "$INPUT_DIR/synthesis_question.txt" ]; then
    SYNTHESIS_FILE="$(realpath "$INPUT_DIR/synthesis_question.txt")"
    echo -e "\n${BLUE}Synthesis mode detected!${NC}"
    echo -e "Found synthesis question: ${GREEN}synthesis_question.txt${NC}"
    echo -e "Will perform meta-analysis after individual processing completes."
fi

# Step 10: Execute batch processing
echo -e "${GREEN}Starting enhanced batch processing...${NC}"

if [ -n "$SYNTHESIS_FILE" ]; then
    apptainer exec --nv --cleanenv \
        --env OLLAMA_HOME=/root/.ollama \
        --env CUDA_VISIBLE_DEVICES=$GPU_LIST \
        --env OLLAMA_NUM_GPU=$NUM_GPUS \
        --env OLLAMA_GPU_LAYERS=999999 \
        --env OLLAMA_NOHISTORY=1 \
        --env TERM=dumb \
        --env NO_COLOR=1 \
        --env SYNTHESIS_MODE=1 \
        --env REASONING_MODE=$REASONING_MODE \
        --env SUPPORTS_REASONING=$SUPPORTS_REASONING \
        --env AUTO_RUN=$AUTO_RUN \
        -B "$STORAGE_PATH:/root/.ollama" \
        -B "$(realpath "$INPUT_DIR"):/input" \
        -B "$(realpath "$BATCH_DIR"):/output" \
        -B "$SYNTHESIS_FILE:/synthesis_question.txt" \
        "$CONTAINER_PATH" /root/.ollama/automated_batch_enhanced.sh
else
    apptainer exec --nv --cleanenv \
        --env OLLAMA_HOME=/root/.ollama \
        --env CUDA_VISIBLE_DEVICES=$GPU_LIST \
        --env OLLAMA_NUM_GPU=$NUM_GPUS \
        --env OLLAMA_GPU_LAYERS=999999 \
        --env OLLAMA_NOHISTORY=1 \
        --env TERM=dumb \
        --env NO_COLOR=1 \
        --env SYNTHESIS_MODE=0 \
        --env REASONING_MODE=$REASONING_MODE \
        --env SUPPORTS_REASONING=$SUPPORTS_REASONING \
        --env AUTO_RUN=$AUTO_RUN \
        -B "$STORAGE_PATH:/root/.ollama" \
        -B "$(realpath "$INPUT_DIR"):/input" \
        -B "$(realpath "$BATCH_DIR"):/output" \
        "$CONTAINER_PATH" /root/.ollama/automated_batch_enhanced.sh
fi

echo -e "\n${BLUE}==== Processing Complete ====${NC}"
echo -e "${GREEN}Batch Directory: $BATCH_DIR${NC}"
echo -e "${GREEN}Summary: $BATCH_DIR/batch_info/batch_summary_$TIMESTAMP.txt${NC}"
echo -e "${GREEN}Technical Log: $BATCH_DIR/batch_info/technical_log_$TIMESTAMP.txt${NC}"
echo -e "${GREEN}Results: $BATCH_DIR/analysis_outputs/${NC}"
echo -e "${GREEN}Prompts: $BATCH_DIR/prompts_archive/${NC}"

if [ $SYNTHESIS_MODE -eq 1 ]; then
    echo -e "${GREEN}Synthesis: $BATCH_DIR/synthesis_analysis/${NC}"
fi

if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" ]]; then
    echo -e "${GREEN}Reasoning: $BATCH_DIR/reasoning_outputs/${NC}"
fi

# Show results summary
if [ -d "$BATCH_DIR" ]; then
    result_count=$(find "$BATCH_DIR/analysis_outputs" -name "*_result.txt" -type f 2>/dev/null | wc -l)
    echo -e "\n${BLUE}Results Summary:${NC}"
    echo -e "   Result files created: $result_count"
    
    if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" ]]; then
        reasoning_count=$(find "$BATCH_DIR/reasoning_outputs" -name "*_thinking.txt" -type f 2>/dev/null | wc -l)
        echo -e "   Reasoning files created: $reasoning_count"
    fi
    
    if [ $result_count -gt 0 ]; then
        echo -e "   Sample files:"
        ls -la "$BATCH_DIR/analysis_outputs"/*_result.txt 2>/dev/null | head -3 | while read line; do
            echo -e "     $line"
        done
        
        # Show first bit of a result to verify cleanliness
        echo -e "\n${BLUE}Sample output (first 150 chars):${NC}"
        head -c 150 "$BATCH_DIR/analysis_outputs"/*_result.txt 2>/dev/null | head -1
    fi
    
    # Show synthesis if it exists
    if [ -f "$BATCH_DIR/synthesis_analysis/SYNTHESIS_FINAL_ANALYSIS.txt" ]; then
        synthesis_size=$(wc -c < "$BATCH_DIR/synthesis_analysis/SYNTHESIS_FINAL_ANALYSIS.txt")
        echo -e "\n${GREEN}Synthesis analysis completed: $synthesis_size characters${NC}"
    fi
    
    # Show reasoning summary if it exists
    if [[ "$SUPPORTS_REASONING" == "true" && "$REASONING_MODE" == "true" && -d "$BATCH_DIR/reasoning_outputs" ]]; then
        reasoning_files=$(find "$BATCH_DIR/reasoning_outputs" -name "*_thinking.txt" -type f | wc -l)
        if [ $reasoning_files -gt 0 ]; then
            total_reasoning_size=$(find "$BATCH_DIR/reasoning_outputs" -name "*_thinking.txt" -exec wc -c {} + | tail -1 | awk '{print $1}')
            echo -e "\n${GREEN}Reasoning processes captured: $reasoning_files files, $total_reasoning_size characters${NC}"
        fi
    fi
fi

echo -e "\n${GREEN}All files preserved in timestamped batch directory!${NC}"
echo -e "\n${BLUE}Command Reference:${NC}"
echo -e "Usage: $0 [model] [input_dir] [output_dir] [num_gpus] [ctx_size] [flags]"
echo -e "Flags: -r (reasoning), -s (skip confirmations), -u DIR (user dir), -h (help)"
echo -e "\n${YELLOW}For detailed help and examples: $0 -h${NC}"