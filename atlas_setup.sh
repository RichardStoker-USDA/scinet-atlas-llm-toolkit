#!/bin/bash
#
# atlas_setup.sh
# Comprehensive setup script for SCINet Atlas LLM Toolkit
# Created by: Richard Stoker (richard.stoker@usda.gov)
# GitHub: https://github.com/RichardStoker-USDA/scinet-atlas-llm-toolkit
#

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_TEST_MODEL="gemma3:1b"
SESSION_USER=$(whoami)

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}  SCINet Atlas LLM Toolkit - Complete Setup  ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}This script will set up your complete LLM workspace${NC}"
echo ""

# Step 1: Get and validate project name
echo -e "${YELLOW}Step 1: Project Validation${NC}"
echo "Please enter your SCINet main project name:"
echo -e "${BLUE}(Example: smith_plantgenomics, jones_soilhealth)${NC}"
read -p "Project name: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Project name cannot be empty${NC}"
    exit 1
fi

PROJECT_PATH="/90daydata/$PROJECT_NAME"
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "${RED}Error: Project directory $PROJECT_PATH does not exist${NC}"
    echo -e "${RED}Please check your project name or contact SCINet support${NC}"
    exit 1
fi

# Test write permissions
if [ ! -w "$PROJECT_PATH" ]; then
    echo -e "${RED}Error: You don't have write permissions to $PROJECT_PATH${NC}"
    echo -e "${RED}Please contact your project PI or SCINet support${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Project validated: $PROJECT_PATH${NC}"
echo ""

# Step 2: Get workspace name
echo -e "${YELLOW}Step 2: Workspace Creation${NC}"
DEFAULT_WORKSPACE="${SESSION_USER}_llm_project"
echo "Enter workspace directory name (press Enter for default):"
echo -e "${BLUE}Default: $DEFAULT_WORKSPACE${NC}"
read -p "Workspace name: " WORKSPACE_NAME

if [ -z "$WORKSPACE_NAME" ]; then
    WORKSPACE_NAME="$DEFAULT_WORKSPACE"
fi

WORKSPACE_PATH="$PROJECT_PATH/$WORKSPACE_NAME"
echo -e "${GREEN}Workspace will be: $WORKSPACE_PATH${NC}"

# Check if workspace exists
if [ -d "$WORKSPACE_PATH" ]; then
    echo -e "${YELLOW}Warning: Workspace already exists${NC}"
    echo "Do you want to continue? (This may overwrite existing files)"
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Setup cancelled${NC}"
        exit 1
    fi
fi

# Create workspace
mkdir -p "$WORKSPACE_PATH"
cd "$WORKSPACE_PATH"
echo -e "${GREEN}✓ Created workspace: $WORKSPACE_PATH${NC}"
echo ""

# Step 3: Create directory structure
echo -e "${YELLOW}Step 3: Directory Structure${NC}"
mkdir -p input_prompts results
echo -e "${GREEN}✓ Created input_prompts/ and results/ directories${NC}"

# Step 4: Ask about test prompts
echo ""
echo -e "${YELLOW}Step 4: Sample Content${NC}"
echo "Do you want to create sample ARS research prompts and synthesis question?"
echo -e "${BLUE}(Press Enter for yes, or type 'no' to skip)${NC}"
read -p "Create samples? (Y/n): " CREATE_SAMPLES

if [[ ! "$CREATE_SAMPLES" =~ ^[Nn] ]]; then
    echo -e "${BLUE}Creating sample prompts...${NC}"
    
    # Create sample prompts
    cat > input_prompts/nutrition_genomics_research.txt << 'EOF'
Analyze the Western Human Nutrition Research Center's contributions to understanding nutrigenomics and metabolic health. Focus on how genetic variations influence individual responses to dietary interventions and the development of personalized nutrition approaches for obesity prevention and metabolic wellness.
EOF

    cat > input_prompts/precision_agriculture_technology.txt << 'EOF'
Examine ARS Davis research in precision agriculture technologies, including hyperspectral drone imaging for canopy cover assessment, automated irrigation optimization systems, and machine learning models for crop health monitoring. Discuss how these technologies improve resource efficiency and yield optimization.
EOF

    cat > input_prompts/germplasm_preservation_research.txt << 'EOF'
Describe the National Clonal Germplasm Repository's work in preserving genetic resources of tree fruits, nuts, and grapes. Include specific methodologies for collection, evaluation, and distribution of plant genetic materials, and the importance of genetic variation for crop improvement and food security.
EOF

    cat > input_prompts/plant_pathology_research.txt << 'EOF'
Investigate the Crops Pathology and Genetics Research Unit's advances in plant disease management, particularly in grape and fruit crop protection. Focus on integrated pest management approaches, disease-resistant variety development, and molecular diagnostic tools for early pathogen detection.
EOF

    cat > input_prompts/synthesis_question.txt << 'EOF'
Based on the analysis of ARS Davis research across nutrition science, agricultural technology, germplasm conservation, and plant health, synthesize the interconnected approaches and identify how these research areas complement each other to advance agricultural productivity and human health outcomes.
EOF

    echo -e "${GREEN}✓ Created 4 sample prompts and synthesis question${NC}"
else
    echo -e "${BLUE}Skipped sample prompt creation${NC}"
fi

echo ""

# Step 5: Copy scripts
echo -e "${YELLOW}Step 5: Script Installation${NC}"
SCRIPT_SOURCE_DIR="$(dirname "$(readlink -f "$0")")/scripts"

if [ -d "$SCRIPT_SOURCE_DIR" ]; then
    cp "$SCRIPT_SOURCE_DIR/ollama_batch_automation.sh" . 2>/dev/null
    cp "$SCRIPT_SOURCE_DIR/ollama_interactive.sh" . 2>/dev/null
    chmod +x ollama_batch_automation.sh ollama_interactive.sh
    echo -e "${GREEN}✓ Copied batch and interactive scripts${NC}"
else
    echo -e "${YELLOW}Note: Could not find scripts directory. Please manually copy:${NC}"
    echo "  - ollama_batch_automation.sh"
    echo "  - ollama_interactive.sh"
fi

# Update PROJECT_NAME in scripts
if [ -f "ollama_batch_automation.sh" ]; then
    sed -i "s/PROJECT_NAME=\"[^\"]*\"/PROJECT_NAME=\"$PROJECT_NAME\"/" ollama_batch_automation.sh
    echo -e "${GREEN}✓ Updated PROJECT_NAME in batch script${NC}"
fi

if [ -f "ollama_interactive.sh" ]; then
    sed -i "s/PROJECT_NAME=\"[^\"]*\"/PROJECT_NAME=\"$PROJECT_NAME\"/" ollama_interactive.sh
    echo -e "${GREEN}✓ Updated PROJECT_NAME in interactive script${NC}"
fi

echo ""

# Step 6: Set up Ollama storage
echo -e "${YELLOW}Step 6: Ollama Storage Setup${NC}"
OLLAMA_STORAGE="$WORKSPACE_PATH/ollama"
mkdir -p "$OLLAMA_STORAGE/models" "$OLLAMA_STORAGE/cache"

# Remove existing .ollama symlink and create new one
if [ -L "$HOME/.ollama" ] || [ -d "$HOME/.ollama" ]; then
    rm -rf "$HOME/.ollama"
fi
ln -s "$OLLAMA_STORAGE" "$HOME/.ollama"
echo -e "${GREEN}✓ Configured Ollama storage in workspace${NC}"

# Step 7: Load modules and download container
echo ""
echo -e "${YELLOW}Step 7: Container Setup${NC}"
echo -e "${BLUE}Loading required modules...${NC}"
module load cuda cudnn apptainer

# Set up Apptainer cache
APPTAINER_CACHE_DIR="$WORKSPACE_PATH/apptainer_cache"
mkdir -p "$APPTAINER_CACHE_DIR/tmp"
export APPTAINER_CACHEDIR="$APPTAINER_CACHE_DIR"
export APPTAINER_TMPDIR="$APPTAINER_CACHE_DIR/tmp"

# Download Ollama container
CONTAINER_PATH="$WORKSPACE_PATH/ollama_latest.sif"
if [ ! -f "$CONTAINER_PATH" ]; then
    echo -e "${BLUE}Downloading Ollama container (this may take a few minutes)...${NC}"
    apptainer pull "$CONTAINER_PATH" docker://ollama/ollama:latest
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Container downloaded successfully${NC}"
    else
        echo -e "${RED}Error downloading container${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Container already exists${NC}"
fi

echo ""

# Step 8: Test setup with small model
echo -e "${YELLOW}Step 8: Testing Setup${NC}"
echo "Do you want to test the setup with a small model ($DEFAULT_TEST_MODEL)?"
echo -e "${BLUE}This will verify everything is working correctly${NC}"
read -p "Test setup? (Y/n): " TEST_SETUP

if [[ ! "$TEST_SETUP" =~ ^[Nn] ]]; then
    echo -e "${BLUE}Starting test with $DEFAULT_TEST_MODEL...${NC}"
    echo -e "${YELLOW}This will start the Ollama server and download the test model${NC}"
    
    # Start Ollama server in background
    apptainer exec --nv --cleanenv \
        --env OLLAMA_HOME=/root/.ollama \
        --env CUDA_VISIBLE_DEVICES=0 \
        --env OLLAMA_NUM_GPU=1 \
        -B "$OLLAMA_STORAGE:/root/.ollama" \
        "$CONTAINER_PATH" ollama serve &
    
    SERVER_PID=$!
    echo -e "${BLUE}Started Ollama server (PID: $SERVER_PID)${NC}"
    
    # Wait for server to start
    echo -e "${BLUE}Waiting for server to initialize...${NC}"
    sleep 10
    
    # Test server connectivity and download model
    echo -e "${BLUE}Downloading and testing $DEFAULT_TEST_MODEL...${NC}"
    apptainer exec --nv --cleanenv \
        --env OLLAMA_HOME=/root/.ollama \
        -B "$OLLAMA_STORAGE:/root/.ollama" \
        "$CONTAINER_PATH" ollama pull "$DEFAULT_TEST_MODEL"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Model downloaded successfully${NC}"
        
        # Test a simple prompt
        echo -e "${BLUE}Testing model with simple prompt...${NC}"
        TEST_RESPONSE=$(apptainer exec --nv --cleanenv \
            --env OLLAMA_HOME=/root/.ollama \
            -B "$OLLAMA_STORAGE:/root/.ollama" \
            "$CONTAINER_PATH" ollama run "$DEFAULT_TEST_MODEL" "Hello, respond with exactly: 'Test successful'" 2>/dev/null | head -1)
        
        if [[ "$TEST_RESPONSE" == *"successful"* ]]; then
            echo -e "${GREEN}✓ Model test successful!${NC}"
        else
            echo -e "${YELLOW}Model downloaded but test response unclear${NC}"
        fi
    else
        echo -e "${RED}Error downloading model${NC}"
    fi
    
    # Stop server
    kill $SERVER_PID 2>/dev/null
    echo -e "${BLUE}Stopped test server${NC}"
else
    echo -e "${BLUE}Skipped setup test${NC}"
fi

echo ""

# Step 9: Final instructions
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}           Setup Complete!                    ${NC}"
echo -e "${GREEN}===============================================${NC}"
echo ""
echo -e "${BLUE}Workspace Location:${NC} $WORKSPACE_PATH"
echo ""
echo -e "${YELLOW}Quick Start Instructions:${NC}"
echo ""
echo -e "${BLUE}1. Test Interactive Mode:${NC}"
echo "   ./ollama_interactive.sh $DEFAULT_TEST_MODEL"
echo ""
echo -e "${BLUE}2. Run Batch Processing:${NC}"
echo "   ./ollama_batch_automation.sh $DEFAULT_TEST_MODEL ./input_prompts ./results 1 131072 -s"
echo ""
echo -e "${BLUE}3. Customize Your Research:${NC}"
echo "   - Edit files in input_prompts/ for your specific research"
echo "   - Delete synthesis_question.txt if you don't need synthesis mode"
echo "   - Try larger models: llama3.3:70b, gemma3:27b, etc."
echo ""
echo -e "${YELLOW}Current Directory:${NC} $(pwd)"
echo -e "${YELLOW}Available Scripts:${NC}"
if [ -f "ollama_batch_automation.sh" ]; then
    echo "   ✓ ollama_batch_automation.sh"
else
    echo "   ✗ ollama_batch_automation.sh (not found)"
fi
if [ -f "ollama_interactive.sh" ]; then
    echo "   ✓ ollama_interactive.sh"
else
    echo "   ✗ ollama_interactive.sh (not found)"
fi

if [[ ! "$CREATE_SAMPLES" =~ ^[Nn] ]]; then
    echo ""
    echo -e "${YELLOW}Sample Files Created:${NC}"
    echo "   ✓ nutrition_genomics_research.txt"
    echo "   ✓ precision_agriculture_technology.txt" 
    echo "   ✓ germplasm_preservation_research.txt"
    echo "   ✓ plant_pathology_research.txt"
    echo "   ✓ synthesis_question.txt"
fi

echo ""
echo -e "${GREEN}Your SCINet Atlas LLM Toolkit is ready to use!${NC}"
echo -e "${BLUE}For help and documentation: https://github.com/RichardStoker-USDA/scinet-atlas-llm-toolkit${NC}"