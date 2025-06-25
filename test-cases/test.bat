@echo off
REM Test the UD validator on a set of short CoNLL-U files.
REM The log file is versioned, so we can check git diff and see if it is OK.
REM Usage: tools\test-cases\test.bat > tools\test-cases\test.log 2>&1
SET "SCRIPT_DIR=%~dp0"
for %%f in ("%SCRIPT_DIR%invalid-level1-2\*.conllu") do (
    @echo --------------------------------------------------------------------------------
    @echo Processing file: %%f
    python %SCRIPT_DIR%..\validate.py --level 2 --lang ud "%%f"
    @echo.
)
@echo --------------------------------------------------------------------------------
@echo LEVEL 3 TESTS
for %%f in ("%SCRIPT_DIR%invalid-level3\*.conllu") do (
    @echo --------------------------------------------------------------------------------
    @echo Processing file: %%f
    python %SCRIPT_DIR%..\validate.py --level 3 --lang ud "%%f"
    @echo.
)
@echo --------------------------------------------------------------------------------
@echo THE FOLLOWING FILES SHOULD BE VALID
for %%f in ("%SCRIPT_DIR%valid\*.conllu") do (
    @echo --------------------------------------------------------------------------------
    @echo Processing file: %%f
    python %SCRIPT_DIR%..\validate.py --level 3 --lang ud "%%f"
    @echo.
)
