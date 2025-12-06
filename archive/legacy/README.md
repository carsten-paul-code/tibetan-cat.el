# Legacy Files

This directory contains archived test files and legacy code from the development of the Tibetan CAT system.

## Contents

These files were used during development but are no longer part of the active system:

### Test Files
- `test-*.el` - Various test scripts for debugging functionality
- `demo-*.el` - Demonstration scripts
- `*-test.el` - Unit and integration tests

### Broken/Deprecated Files
- `*-BROKEN.el` - Files that had known issues
- Older versions of current modules

## Why Archived?

These files were moved here during the modularization refactoring (v1.0.0) to:
1. Keep the main codebase clean
2. Preserve development history
3. Allow reference to old implementations if needed

## Usage

These files are **not loaded** by the main system. They are kept for:
- Historical reference
- Understanding development decisions
- Potential code recovery if needed

## Active System

For the current, working system, see the main directory:
- `core/` - Core functionality
- `analysis/` - Analysis modules
- `workspace/` - Workspace modules
- `config/` - Configuration

See `../README.md` for full documentation.
