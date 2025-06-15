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

# Get the directory where atlas_setup.sh is located
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${BLUE}Setup script location: $SETUP_DIR${NC}"

# Try multiple possible locations for scripts
SCRIPTS_COPIED=false

# Location 1: scripts/ subdirectory relative to setup script
if [ "$SCRIPTS_COPIED" = false ] && [ -f "$SETUP_DIR/scripts/ollama_batch_automation.sh" ]; then
    if cp "$SETUP_DIR/scripts/ollama_batch_automation.sh" . 2>/dev/null && \
       cp "$SETUP_DIR/scripts/ollama_interactive.sh" . 2>/dev/null; then
        chmod +x ollama_batch_automation.sh ollama_interactive.sh
        echo -e "${GREEN}✓ Copied scripts from: $SETUP_DIR/scripts/${NC}"
        SCRIPTS_COPIED=true
    fi
fi

# Location 2: Current working directory when setup was run  
ORIGINAL_DIR="$(pwd)"
TEMP_DIR="$ORIGINAL_DIR"
if [ "$SCRIPTS_COPIED" = false ]; then
    # Check if we're not already in the workspace
    if [ "$ORIGINAL_DIR" != "$WORKSPACE_PATH" ]; then
        cd "$ORIGINAL_DIR" 2>/dev/null || true
        
        if [ -f "scripts/ollama_batch_automation.sh" ]; then
            if cp "scripts/ollama_batch_automation.sh" "$WORKSPACE_PATH/" 2>/dev/null && \
               cp "scripts/ollama_interactive.sh" "$WORKSPACE_PATH/" 2>/dev/null; then
                cd "$WORKSPACE_PATH"
                chmod +x ollama_batch_automation.sh ollama_interactive.sh
                echo -e "${GREEN}✓ Copied scripts from: $ORIGINAL_DIR/scripts/${NC}"
                SCRIPTS_COPIED=true
            fi
        fi
    fi
fi

# Go back to workspace
cd "$WORKSPACE_PATH"

if [ "$SCRIPTS_COPIED" = false ]; then
    echo -e "${YELLOW}Warning: Could not automatically copy scripts${NC}"
    echo -e "${YELLOW}Please run these commands to copy scripts manually:${NC}"
    echo ""
    echo -e "${BLUE}cd $ORIGINAL_DIR${NC}"
    echo -e "${BLUE}cp scripts/ollama_batch_automation.sh $WORKSPACE_PATH/${NC}"
    echo -e "${BLUE}cp scripts/ollama_interactive.sh $WORKSPACE_PATH/${NC}"
    echo -e "${BLUE}cd $WORKSPACE_PATH${NC}"
    echo -e "${BLUE}chmod +x ollama_batch_automation.sh ollama_interactive.sh${NC}"
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
    echo -e "${BLUE}Testing container access...${NC}"
    
    # Simple container test - just verify we can run basic commands
    echo -e "${BLUE}Testing Ollama container functionality...${NC}"
    if apptainer exec --nv --cleanenv \
        --env OLLAMA_HOME=/root/.ollama \
        -B "$OLLAMA_STORAGE:/root/.ollama" \
        "$CONTAINER_PATH" ollama --version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Container test successful!${NC}"
        echo -e "${BLUE}Container is ready for use${NC}"
    else
        echo -e "${YELLOW}Container test had issues, but setup continues...${NC}"
    fi
    
    echo -e "${BLUE}Note: Model downloading and testing will be done when you run the scripts${NC}"
    echo -e "${BLUE}Use './ollama_interactive.sh $DEFAULT_TEST_MODEL' to test with the small model${NC}"
else
    echo -e "${BLUE}Skipped container test${NC}"
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

echo ""
echo -e "${YELLOW}Switching to your workspace directory...${NC}"
cd "$WORKSPACE_PATH"

# Use exec to replace the current shell process with a new one in the workspace
echo -e "${GREEN}You are now in: $(pwd)${NC}"
echo -e "${BLUE}Ready to run: ./ollama_interactive.sh $DEFAULT_TEST_MODEL${NC}"
echo ""

# Start a new shell in the workspace directory
exec bash