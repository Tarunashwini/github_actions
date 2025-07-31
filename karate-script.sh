#!/bin/bash -e

# --- GitHub Actions Input Handling ---
# These variables are passed from the GitHub Actions workflow as environment variables
# GH_ACTIONS_ENVIRONMENT: Corresponds to 'environment' input
# GH_ACTIONS_MODULE_NAME: Corresponds to 'module_name' input
# GH_ACTIONS_SCRIPT_NAME: Corresponds to 'script_name' input
# GH_ACTIONS_CLEAR_CACHE: Corresponds to 'clear_cache' input

# Set defaults from GitHub Actions inputs, if provided
TEST_STAGE="${GH_ACTIONS_ENVIRONMENT:-pp}" # Use input, or default to 'pp' if not provided
CLEAR_CACHE="${GH_ACTIONS_CLEAR_CACHE:-true}" # Use input, or default to 'true'

# --- Paths and Cache Clearing ---
KARATE_TEST_FILES_ROOT_DIR="pavillio-monorepo/cashe20/pavillio-karate-script/karate-test-files"
# Adjust this if your actual Karate JAR is in a different location relative to this script
KARATE_JAR_PATH="${KARATE_TEST_FILES_ROOT_DIR}/karate-1.2.0.jar"
KARATE_OUTPUT_PATH="C:/Users/poornachandra.b/Documents/karate-test-reports" # This path is Windows-specific, might need adjustment for Linux runner

if [ "$CLEAR_CACHE" == "true" ] && [ -d "${KARATE_TEST_FILES_ROOT_DIR}/.cache" ]; then
  echo "Clearing cache directory: ${KARATE_TEST_FILES_ROOT_DIR}/.cache"
  rm -rf "${KARATE_TEST_FILES_ROOT_DIR}/.cache"
fi

# --- Test Suite Construction ---
BASE_TEST_PATH="cashe20/pavillio-karate-script" # This is the base relative path

# Construct TEST_SUITE and FEATURE_TO_RUN dynamically
if [ -n "$GH_ACTIONS_MODULE_NAME" ]; then
  # Module name provided
  TEST_SUITE="${BASE_TEST_PATH}/${GH_ACTIONS_MODULE_NAME}"
  if [ -n "$GH_ACTIONS_SCRIPT_NAME" ]; then
    # Specific script name provided within the module
    FEATURE_TO_RUN="${GH_ACTIONS_MODULE_NAME}/${GH_ACTIONS_SCRIPT_NAME}"
    echo "Running specific script: ${FEATURE_TO_RUN} in module: ${GH_ACTIONS_MODULE_NAME}"
  else
    # Run all scripts in the provided module
    FEATURE_TO_RUN="${GH_ACTIONS_MODULE_NAME}"
    echo "Running all scripts in module: ${GH_ACTIONS_MODULE_NAME}"
  fi
else
  # No module name provided, run all modules from the base path
  TEST_SUITE="${BASE_TEST_PATH}" # This will be the root for test discovery
  FEATURE_TO_RUN="" # An empty string or '.' usually tells Karate to discover all
  echo "Running all scripts from all modules under: ${BASE_TEST_PATH}"
fi

# Determine CASHE_TOOLS
if [ -z "$CASHE_TOOLS" ]; then
  echo "CASHE_TOOLS not set. Defaulting to script directory."
  CASHE_TOOLS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
  echo "CASHE_TOOLS set to $CASHE_TOOLS"
fi

# --- Validation (Simplified as inputs are now controlled by GHA) ---
# Removed the `exit` conditions for TEST_STAGE and TEST_SUITE as they are now handled by GHA inputs.
# You can keep more robust validation if needed for local runs.

# --- Setup Module and Stage Specific Exports ---
# IMPORTANT: Adjust these paths. They should be relative to where your 'run-automation-tests.sh' script is executed from,
# or absolute paths if CASHE_TOOLS resolves to an absolute path.
# Assuming KARATE_TEST_FILES_ROOT_DIR is the correct base for these files.

MODULE_EXPORTS_FILE="${CASHE_TOOLS}/${GH_ACTIONS_MODULE_NAME}/test_exports.sh"
if [ -n "$GH_ACTIONS_MODULE_NAME" ] && [ -f "$MODULE_EXPORTS_FILE" ]; then
  echo "Executing module level exports ${MODULE_EXPORTS_FILE}"
  . "$MODULE_EXPORTS_FILE" || { echo 'setting module exports failed' ; exit 3; }
else
  echo "No module exports found or module not specified."
fi

STAGE_EXPORTS_FILE="${KARATE_TEST_FILES_ROOT_DIR}/${TEST_STAGE}_exports.sh"
if [ -f "$STAGE_EXPORTS_FILE" ]; then
  echo "Executing test stage level exports ${STAGE_EXPORTS_FILE}"
  . "$STAGE_EXPORTS_FILE" || { echo 'setting stage level exports failed' ; exit 4; }
else
  echo "No stage level exports found for stage: ${TEST_STAGE}"
fi

# --- Setup Stage Level Users and Tokens ---
STAGE_USERS_PROPERTIES="${KARATE_TEST_FILES_ROOT_DIR}/${TEST_STAGE}_users.properties"
GET_AWS_TOKENS_SCRIPT="${KARATE_TEST_FILES_ROOT_DIR}/get-aws-tokens.sh"

if [ -f "$STAGE_USERS_PROPERTIES" ]; then
  if [ -f "$GET_AWS_TOKENS_SCRIPT" ]; then
    echo "Setting up stage level users and tokens $GET_AWS_TOKENS_SCRIPT $STAGE_USERS_PROPERTIES"
    . "$GET_AWS_TOKENS_SCRIPT" "$STAGE_USERS_PROPERTIES" || { echo 'failed setting tokens' ; exit 5; }
  else
    echo "Error: get-aws-tokens.sh not found at ${GET_AWS_TOKENS_SCRIPT}"
    exit 5
  fi
else
  echo "Missing stage users : ${STAGE_USERS_PROPERTIES}"
  exit 6
fi

# --- Execute Tests ---
echo "Executing tests for environment: ${TEST_STAGE}"

# Construct the Karate command
KARATE_COMMAND="java -Dkarate.output.path=\"${KARATE_OUTPUT_PATH}\" -jar \"${KARATE_JAR_PATH}\""

if [ -n "$FEATURE_TO_RUN" ]; then
  # If a specific module or script is designated
  KARATE_COMMAND="${KARATE_COMMAND} ${KARATE_TEST_FILES_ROOT_DIR}/${FEATURE_TO_RUN}"
else
  # If no module/script, Karate should discover all under the root
  KARATE_COMMAND="${KARATE_COMMAND} ${KARATE_TEST_FILES_ROOT_DIR}"
fi

# Optional: Add tags if you want to support them via another input
# KARATE_COMMAND="${KARATE_COMMAND} --tags @Runme" # Example if you want to hardcode or add another input for tags

echo "Running Karate command: ${KARATE_COMMAND}"
eval ${KARATE_COMMAND} || { echo 'Karate tests failed!' ; exit 7; }

echo "Karate tests finished."
