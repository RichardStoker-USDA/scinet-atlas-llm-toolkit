# SCINet Atlas LLM Toolkit

Automation toolkit for running Large Language Models on USDA SCINet Atlas HPC cluster.

## Full Documentation

**View the complete user manual for detailed setup instructions and usage examples:**

**<a href="https://richardstoker-usda.github.io/scinet-atlas-llm-toolkit/" target="_blank">Complete Manual</a>**

The manual covers everything you need including setup, troubleshooting, model recommendations, and complete script documentation.

## What This Does

This toolkit lets you run Large Language Models on Atlas with full automation. You save your prompts as text files, point the script to that directory, and specify where you want results saved. The scripts handle GPU allocation, model loading, and batch processing automatically.

Key features:
- Batch processing for multiple prompts
- Interactive mode for real-time testing
- Multi-GPU support (up to 6 A100s, 480GB VRAM total)
- Large context windows (128k+ tokens)
- All processing stays within SCINet infrastructure

## Scripts

- `atlas_setup.sh` - Complete automated setup script
- `scripts/ollama_batch_automation.sh` - Processes multiple prompt files automatically
- `scripts/ollama_interactive.sh` - Interactive chat mode for testing

## Requirements

- SCINet Atlas account with GPU access
- Atlas Open OnDemand interface access
- Access to a project that gives access to GPUs as well

## Quick Start

**Automated Setup (Recommended):**
1. Clone this repository: `git clone https://github.com/RichardStoker-USDA/scinet-atlas-llm-toolkit.git`
2. Run the setup script: `./atlas_setup.sh`
3. Follow the prompts to configure your workspace

**Manual Setup:**
1. Read the <a href="https://richardstoker-usda.github.io/scinet-atlas-llm-toolkit/" target="_blank">complete manual</a>
2. Download the scripts from the `scripts/` directory  
3. Update the `PROJECT_NAME` variable in both scripts to match your Atlas project
4. Follow the detailed setup instructions in the manual

## Contact

Richard Stoker  
IT Specialist | Scientific Support  
REE/ARS | ITSD  
Davis, CA  
richard.stoker@usda.gov

## What is SCINet?

The SCINet initiative is an effort by the USDA [Agricultural Research Service (ARS)](https://www.ars.usda.gov/) to grow USDA's research capacity by providing scientists with access to high-performance computing clusters, high-speed networking for data transfer, and training in scientific computing.

For more information about SCINet Atlas and getting an account, visit: https://scinet.usda.gov/
