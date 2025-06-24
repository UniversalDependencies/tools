@echo off
REM Test the UD validator on a set of short CoNLL-U files.
REM The log file is versioned, so we can check git diff and see if it is OK.
REM Usage: tools\test-cases\test.bat > tools\test-cases\test.log 2>&1
SET "SCRIPT_DIR=%~dp0"
for %%f in ("%SCRIPT_DIR%nonvalid\*.conllu") do (
    @echo --------------------------------------------------------------------------------
    @echo Processing file: %%f
    python %SCRIPT_DIR%..\validate.py --level 2 --lang ud "%%f"
    @echo.
)
