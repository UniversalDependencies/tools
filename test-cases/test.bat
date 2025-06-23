@echo off
SET "SCRIPT_DIR=%~dp0"
for %%f in ("%SCRIPT_DIR%nonvalid\*.conllu") do (
    @echo --------------------------------------------------------------------------------
    @echo Processing file: %%f
    python %SCRIPT_DIR%..\validate.py --lang en "%%f"
    @echo.
)
